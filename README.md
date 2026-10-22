# חופה ישראלית – אתר

אתר בעברית (RTL) לעסק השכרת חופות בצפון ובחיפה: עמוד נחיתה + בלוג.

- כתובת האתר: https://chupay.github.io/chupa_yisraelit/
- אחסון: GitHub Pages, נבנה אוטומטית עם Jekyll מכל דחיפה (push) לענף `main`.

---

## 📁 מבנה התיקייה

| קובץ / תיקייה | מה זה |
|---|---|
| `index.html` | עמוד הנחיתה – כל ה-HTML, ה-CSS וה-JavaScript בקובץ אחד. Jekyll מעתיק אותו כמו שהוא. |
| `blog/index.html` | עמוד הבלוג (`/blog/`) – רשימת המאמרים ככרטיסים, עם דפדוף. |
| `_posts/` | מאמרי הבלוג, קובץ Markdown לכל מאמר. |
| `_layouts/blog_post.html` | התבנית שבה מוצג כל מאמר. |
| `chuppah-haifa.html`, `outdoor-wedding.html`, `keywords.html` | עמודי SEO קצרים. |
| `assets/` | תמונות ולוגו (בעיקר `.webp`). |
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
   card_image: /assets/my-image.webp
   card_image_alt: "תיאור התמונה"
   tags: ["תגית", "עוד תגית"]
   ---
   ```
3. מתחת – תוכן המאמר ב-Markdown (`##` לכותרות משנה).
4. לשמור את התמונה ב-`assets/`.

המאמר יופיע אוטומטית בעמוד הבלוג וב-sitemap.

---

## 🛠️ עריכת עמוד הנחיתה (`index.html`)

סקשנים לפי סדר: `#about` · `#products` · `#areas` · `#photos` · `#testimonials` · `#faq` · `#contact`

- **טקסטים** – לחפש את הטקסט בקובץ ולהחליף.
- **מחירים** – מופיעים בשני מקומות: כרטיס המוצר (`class="price"`) ותשובה בשאלות הנפוצות.
- **תמונות ברצועה המתחלפת** – רשימת `photoPool` בסקריפט בתחתית הקובץ.
- **מוצר חדש** – לשכפל `<article class="product">` ולהחליף את כל המופעים של `prod1`/`prod2` (`id`, `aria-labelledby`, `aria-controls`, `data-toggle`, `data-gallery`).
- **גלריה** – כל תמונה בתוך `class="gallery"` נפתחת במסך מלא בלחיצה.
- **סקשן חדש** – `<section id="...">` בתוך `<main>` + קישור בתפריט `<nav class="menu">`.
- **צבעים** – משתני CSS בתחילת `<style>` (`--brand`, `--accent` וכו').
- **WhatsApp / טלפון** – המספר מופיע בכפתור הצף (`id="wa-float"`), בסקשן `#contact` ובנתוני ה-schema בראש הקובץ.

### SEO
בראש `index.html`: `title`, `description`, תגיות Open Graph (תצוגה בשיתוף בוואטסאפ/פייסבוק), ונתוני schema (`application/ld+json`) עם פרטי העסק. כשמשנים טלפון, אזורים או קישורים – לעדכן גם שם.

---

## 📊 שירותים מחוברים
- **Google Analytics** – `G-427E24BETT` (בעמוד הנחיתה ובמאמרים).
- **Google Search Console** – אימות דרך תגית `google-site-verification` ב-`index.html`. לא למחוק.
