# חופה ישראלית – אתר

אתר בעברית (RTL) לעסק השכרת חופות בצפון ובחיפה: עמוד נחיתה + בלוג.

- כתובת האתר: https://chupay.github.io/chupa_yisraelit/
- אחסון: GitHub Pages, נבנה אוטומטית עם Jekyll מכל דחיפה (push) לענף `main`.

---

## 📁 מבנה התיקייה

| קובץ / תיקייה | מה זה |
|---|---|
| `index.html` | עמוד הנחיתה – התוכן. העיצוב ב-`assets/css/home.css`, ה-JavaScript ב-`assets/js/home.js`, התפריט והפוטר מ-`_includes/`. |
| `blog/index.html` | עמוד הבלוג (`/blog/`) – רשימת המאמרים ככרטיסים, עם דפדוף. |
| `_posts/` | מאמרי הבלוג, קובץ Markdown לכל מאמר. |
| `_layouts/blog_post.html` | התבנית שבה מוצג כל מאמר. |
| `_includes/` | חלקים משותפים לכל העמודים: `head-common.html` (אייקונים + Google Analytics), `site-header.html` (לוגו ותפריט), `site-footer.html` (כפתור WhatsApp ופוטר). שינוי כאן משנה את כל האתר. |
| `assets/css/site-chrome.css` | העיצוב של התפריט, הפוטר וכפתור ה-WhatsApp. |
| `chuppah-haifa.html`, `outdoor-wedding.html`, `keywords.html` | עמודי SEO קצרים. |
| `assets/img/` | תמונות, לפי תיקיות: `brand/` (לוגו), `products/` (מוצרים ותמונה ראשית), `gallery/` (תמונות מאירועים), `blog/` (תמונות מאמרים). שמות קבצים באנגלית, שמתארים מה בתמונה. |
| `_config.yml` | הגדרות Jekyll: כתובת, שפה, פלאגינים, דפדוף בבלוג. |
| `robots.txt` | הנחיות למנועי חיפוש. מפנה ל-`sitemap.xml`. |
| `Gemfile` | לתצוגה מקומית בלבד (לא משפיע על האתר החי). |

`sitemap.xml` ו-`feed.xml` נוצרים אוטומטית בבנייה (פלאגינים `jekyll-sitemap` ו-`jekyll-feed`) – אין לכתוב אותם ידנית.

---

## 🖥️ תצוגה מקומית (לפני שמעלים לאוויר)

התקנה חד-פעמית:
1. להתקין Ruby+Devkit מ-https://rubyinstaller.org (ברירות המחדל).
2. בתיקיית הפרויקט: `bundle install`

בכל פעם:
```
bundle exec jekyll serve
```
ואז לפתוח http://localhost:4000/chupa_yisraelit/ – האתר מתעדכן אוטומטית בכל שמירה.

---

## 🚀 העלאה לאוויר

GitHub Pages מפרסם רק את ענף `main`.
מומלץ לעבוד על ענף נפרד, לבדוק מקומית, ורק אז למזג ל-`main`:
```
git switch -c my-change
# ...עריכה ובדיקה מקומית...
git commit -am "תיאור קצר של השינוי"
git switch main
git merge my-change
git push
```
אחרי כדקה-שתיים השינוי באוויר.

---

## ✍️ הוספת מאמר לבלוג

1. ליצור קובץ ב-`_posts/` בשם `YYYY-MM-DD-short-name.md` (התאריך בשם הקובץ הוא תאריך הפרסום).
2. בראש הקובץ:
   ```yaml
   ---
   layout: blog_post
   title: "כותרת המאמר"
   description: "תקציר קצר – מופיע בכרטיס בבלוג ובגוגל"
   permalink: /blog/short-name/
   card_image: /assets/img/blog/my-image.webp
   card_image_alt: "תיאור התמונה"
   tags: ["תגית", "עוד תגית"]
   ---
   ```
3. מתחת – תוכן המאמר ב-Markdown (`##` לכותרות משנה).
4. לשמור את התמונה ב-`assets/img/blog/`.

המאמר יופיע אוטומטית בעמוד הבלוג וב-sitemap.

---

## 🛠️ עריכת עמוד הנחיתה (`index.html`)

סקשנים לפי סדר: `#about` · `#products` · `#areas` · `#photos` · `#testimonials` · `#faq` · `#contact`

- **טקסטים** – לחפש את הטקסט בקובץ ולהחליף.
- **מחירים** – מופיעים בשני מקומות: כרטיס המוצר (`class="price"`) ותשובה בשאלות הנפוצות.
- **תמונות ברצועה המתחלפת** – רשימת `photoPool` ב-`assets/js/home.js`. כל תמונה מוצגת אותו זמן; הרצועה עוצרת כשהיא לא על המסך, כשהעכבר עליה או כשתמונה פתוחה במסך מלא.
- **מוצר חדש** – לשכפל `<article class="product">` ולהחליף את כל המופעים של `prod1`/`prod2` (`id`, `aria-labelledby`, `aria-controls`, `data-toggle`, `data-gallery`).
- **גלריה** – כל תמונה בתוך `class="gallery"` נפתחת במסך מלא בלחיצה.
- **סקשן חדש** – `<section id="...">` בתוך `<main>` + קישור בתפריט ב-`_includes/site-header.html`.
- **צבעים** – משתני CSS בתחילת `assets/css/home.css` (`--brand`, `--accent` וכו').
- **WhatsApp / טלפון** – המספר מופיע בכפתור הצף (`_includes/site-footer.html`), בסקשן `#contact`, בנתוני ה-schema בראש `index.html` ובעמוד `404.html`.

### SEO
בראש `index.html`: `title`, `description`, תגיות Open Graph (תצוגה בשיתוף בוואטסאפ/פייסבוק), ונתוני schema (`application/ld+json`) עם פרטי העסק. כשמשנים טלפון, אזורים או קישורים – לעדכן גם שם.

---

## 📊 שירותים מחוברים
- **Google Analytics** – `G-427E24BETT`, בכל העמודים דרך `_includes/head-common.html`.
- **Google Search Console** – אימות דרך תגית `google-site-verification` ב-`index.html`. לא למחוק.
