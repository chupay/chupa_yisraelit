# import os
# import pytest


# def pytest_configure(config):
#     # 仅在工作节点设置设备ID
#     if hasattr(config, "workerinput"):
#         worker_id = config.workerinput["workerid"]
#         device_id = int(worker_id.replace("gw", ""))
#         os.environ["ASCEND_DEVICE_ID"] = str(device_id)
#         print(f"\n>> Worker {worker_id} using NPU device {device_id}")


# # 可选：设备初始化逻辑
# @pytest.fixture(scope="session", autouse=True)
# def init_npu_device():
#     if "ASCEND_DEVICE_ID" in os.environ:
#         device_id = os.environ["ASCEND_DEVICE_ID"]
#         # 在此处添加设备初始化代码
#         print(f"Initializing NPU device {device_id}")

import pytest
import torch
import torch_npu
import os
import hashlib
import inspect
from contextlib import contextmanager


@pytest.fixture(scope="session", autouse=True)
def assign_npu(worker_id):
    """Original fixture - unchanged"""
    npu_count = torch.npu.device_count()
    if worker_id == "master":
        npu_id = 0
    else:
        idx = int(worker_id.replace("gw", ""))
        npu_id = idx % npu_count
    torch.npu.set_device(npu_id)


@contextmanager
def create_profiler(torch_path):
    """
    Profiler from utils.py - exact copy
    """
    experimental_config = torch_npu.profiler._ExperimentalConfig(
        aic_metrics=torch_npu.profiler.AiCMetrics.PipeUtilization,
        profiler_level=torch_npu.profiler.ProfilerLevel.Level0,
    )
    profile_path = torch_path
    with torch_npu.profiler.profile(
        activities=[torch_npu.profiler.ProfilerActivity.NPU],
        record_shapes=False,
        profile_memory=False,
        with_stack=False,
        schedule=torch_npu.profiler.schedule(wait=0, warmup=2, active=2, repeat=1, skip_first=2),
        on_trace_ready=torch_npu.profiler.tensorboard_trace_handler(profile_path),
        experimental_config=experimental_config
    ) as prof:
        yield prof


def _generate_profile_dir_name(test_name, test_params):
    """Generate directory name from test parameters"""
    param_parts = []
    
    for key, value in test_params.items():
        if isinstance(value, tuple):
            shape_str = "x".join(str(x) for x in value)
            param_parts.append(f"{key}_{shape_str}")
        elif isinstance(value, (int, float)):
            param_parts.append(f"{key}_{value}")
        elif isinstance(value, str):
            clean_value = value.replace(".", "").replace("-", "")
            param_parts.append(f"{key}_{clean_value}")
        else:
            param_parts.append(f"{key}_{str(value)}")
    
    dir_name = "_".join(param_parts)
    
    if len(dir_name) > 200:
        hash_suffix = hashlib.md5(dir_name.encode()).hexdigest()[:8]
        dir_name = dir_name[:190] + "_" + hash_suffix
    
    return dir_name


def pytest_addoption(parser):
    """Add command-line options for profiling"""
    parser.addoption(
        "--profile",
        action="store_true",
        default=False,
        help="Enable NPU profiling for all tests"
    )
    parser.addoption(
        "--profile-dir",
        action="store",
        default="profile_results",
        help="Base directory for profiling results (default: profile_results)"
    )

def do_profile_test(test_func, test_args, profile_path, rep=10):
    """
    Profile a test function following utils.py do_bench_using_profiling_npu pattern.
    
    Args:
        test_func: The test function to profile
        test_args: Dictionary of test function arguments (only actual test params, not fixtures)
        profile_path: Path where profiling results will be saved
        rep: Number of repetitions (default: 10)
    """
    stream = torch.npu.current_stream()
    stream.synchronize()
    
    with create_profiler(profile_path) as prof:
        stream.synchronize()
        
        # Execute test function multiple times with prof.step() after each call
        # Following utils.py pattern: for _ in range(rep + 10)
        for _ in range(rep + 10):
            test_func(**test_args)
            prof.step()
        
        stream.synchronize()


@pytest.hookimpl(hookwrapper=True)
def pytest_pyfunc_call(pyfuncitem):
    """
    Hook that intercepts test function calls.
    When profiling is enabled, replaces normal execution with profiled execution.
    """
    enable_profile = pyfuncitem.config.getoption("--profile", default=False)
    
    if not enable_profile:
        # No profiling, run test normally
        yield
        return
    
    test_function_name = pyfuncitem.originalname or pyfuncitem.name

    test_params = {}
    if hasattr(pyfuncitem, 'callspec'):
        test_params = pyfuncitem.callspec.params.copy()

    base_profile_dir = pyfuncitem.config.getoption("--profile-dir", default="profile_results")

    test_func_dir = os.path.join(base_profile_dir, test_function_name)
    
    if test_params:
        param_dir_name = _generate_profile_dir_name(test_function_name, test_params)
        profile_path = os.path.join(test_func_dir, param_dir_name)
    else:
        profile_path = os.path.join(test_func_dir, "run_0")

    os.makedirs(profile_path, exist_ok=True)

    testfunction = pyfuncitem.obj
    
    sig = inspect.signature(testfunction)
    func_params = set(sig.parameters.keys())
    
    funcargs = pyfuncitem.funcargs
    filtered_args = {k: v for k, v in funcargs.items() if k in func_params}

    do_profile_test(testfunction, filtered_args, profile_path, rep=10)

    print(f"\nProfile saved to: {profile_path}")
    
    outcome = yield
    outcome.force_result(None)