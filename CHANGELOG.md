# Changelog

🇷🇺 Русское описание и 🇬🇧 English description приведены для каждого релиза.

---

## v0.7 — Unified Live Line + Live Perimeter

### 🇷🇺 Русский

- Добавлен новый основной файл `MLeaderSmartAlign_v07.lsp`.
- v0.7 стала полностью **standalone**:
  - не требуется `MLeaderSmartAlign_v05.lsp`;
  - не требуется `MLeaderSmartAlign_Perimeter_v01_fix1.lsp`.
- Линейный SmartAlign и Perimeter объединены в один интерактивный workflow.
- Добавлен двухэтапный режим:
  - Stage 1 — `LIVE LINE`;
  - Stage 2 — optional `LIVE PERIMETER`.
- После выбора первой точки `P1` движение курсора сразу показывает Live Preview линейного распределения.
- Второй клик фиксирует `P2` и делает линейное распределение базовым результатом.
- После `P2`:
  - `Esc` / правая кнопка мыши оставляет линейное распределение;
  - движение курсора в сторону запускает Live Perimeter;
  - клик по `P3` фиксирует Perimeter.
- Во время Perimeter Preview `Esc` возвращает к уже принятому линейному распределению `P1 → P2`, а не к исходной геометрии.
- Четвёртая вершина Perimeter рассчитывается автоматически:
  - `P4 = P1 + (P3 - P2)`.
- Две диагонали делят параллелограмм на четыре геометрические области.
- Каждый MLeader классифицируется по исходной representative Arrow Point.
- Boundary / outside Arrow Points назначаются ближайшей стороне.
- Каждая сторона независимо использует тот же итерационный SmartAlign-алгоритм:
  - `N → N-1 → N-2 → ... → 1`.
- Сохранена content-aware логика из v0.5:
  - MText → горизонтальный центр текста на уровне landing;
  - Block → block content point;
  - fallback → representative landing point.
- Сохранено восстановление исходных Arrowhead Points после перемещения.
- Сохранено адаптивное throttling Live Preview для больших выборок.
- Добавлены пользовательские команды:
  - `MSA7`
  - `MLEADERSMARTALIGN`
- Обе команды запускают один и тот же v0.7 workflow.
- Добавлена демонстрация `images/MLeaderSmartAlign_v07.gif`.

### 🇬🇧 English

- Added new main file `MLeaderSmartAlign_v07.lsp`.
- v0.7 is now fully **standalone**:
  - `MLeaderSmartAlign_v05.lsp` is no longer required;
  - `MLeaderSmartAlign_Perimeter_v01_fix1.lsp` is no longer required.
- Line SmartAlign and Perimeter are combined into one interactive workflow.
- Added a two-stage mode:
  - Stage 1 — `LIVE LINE`;
  - Stage 2 — optional `LIVE PERIMETER`.
- After picking the first point `P1`, cursor movement immediately shows a live linear distribution preview.
- The second click fixes `P2` and makes the linear layout the baseline result.
- After `P2`:
  - `Esc` / right-click keeps the linear layout;
  - moving the cursor sideways starts Live Perimeter;
  - clicking `P3` accepts the Perimeter layout.
- During Perimeter Preview, `Esc` returns to the accepted `P1 → P2` linear layout instead of restoring the original geometry.
- The fourth Perimeter vertex is calculated automatically:
  - `P4 = P1 + (P3 - P2)`.
- Two diagonals divide the parallelogram into four geometric regions.
- Each MLeader is classified using its original representative Arrow Point.
- Boundary / outside Arrow Points are assigned to the nearest side.
- Each side independently uses the same iterative SmartAlign algorithm:
  - `N → N-1 → N-2 → ... → 1`.
- Preserved the v0.5 content-aware placement logic:
  - MText → horizontal text center on landing level;
  - Block → block content point;
  - fallback → representative landing point.
- Preserved original Arrowhead restoration after movement.
- Preserved adaptive Live Preview throttling for large selections.
- Added user commands:
  - `MSA7`
  - `MLEADERSMARTALIGN`
- Both commands launch the same v0.7 workflow.
- Added demo `images/MLeaderSmartAlign_v07.gif`.

---

## MLeaderSmartAlign Perimeter v0.1

### 🇷🇺 Русский

- Добавлен отдельный режим автоматического распределения `MULTILEADER` по периметру параллелограмма.
- Добавлен файл `MLeaderSmartAlign_Perimeter_v01_fix1.lsp`.
- Добавлены команды `MSAP` и `MLeaderSmartAlignPerimeter`.
- Параллелограмм задаётся тремя точками `P1 → P2 → P3`.
- Четвёртая вершина рассчитывается автоматически: `P4 = P1 + (P3 - P2)`.
- Добавлено интерактивное построение сторон с временной пунктирной графикой.
- Две диагонали делят область на четыре треугольных сектора.
- Каждый MLeader классифицируется по исходной representative Arrow Point.
- Точки на границе или вне параллелограмма назначаются ближайшей стороне.
- Каждая сторона использует итерационный SmartAlign-алгоритм из v0.5.
- MLeader размещаются пошагово.
- Исходные Arrowhead Points сохраняются.
- Временная геометрия не записывается в DWG.
- Добавлена демонстрация `images/MLeaderSmartAlign_Perimeter.gif`.
- Исправлена ошибка AutoLISP `incorrect object to bind: T`: локальные / формальные переменные `t` переименованы в `ratio` / `param`.
- Эта версия требует загрузки `MLeaderSmartAlign_v05.lsp`.

### 🇬🇧 English

- Added a separate mode for automatically distributing `MULTILEADER` objects around a parallelogram perimeter.
- Added `MLeaderSmartAlign_Perimeter_v01_fix1.lsp`.
- Added commands `MSAP` and `MLeaderSmartAlignPerimeter`.
- The parallelogram is defined by three points: `P1 → P2 → P3`.
- The fourth vertex is calculated automatically: `P4 = P1 + (P3 - P2)`.
- Added interactive side definition with transient dashed graphics.
- Two diagonals divide the area into four triangular regions.
- Each MLeader is classified using its original representative Arrow Point.
- Boundary or outside points are assigned to the nearest side.
- Every side uses the iterative SmartAlign algorithm from v0.5.
- MLeaders are placed step by step.
- Original Arrowhead Points are preserved.
- Temporary helper geometry is not stored in the DWG.
- Added demo `images/MLeaderSmartAlign_Perimeter.gif`.
- Fixed AutoLISP error `incorrect object to bind: T`: local / formal variables named `t` were renamed to `ratio` / `param`.
- This version requires `MLeaderSmartAlign_v05.lsp`.

---

## v0.5

### 🇷🇺 Русский

- Добавлена content-aware точка размещения.
- MText использует горизонтальный центр текста, спроецированный на landing line.
- Блочное / круглое содержимое использует позицию блока.
- Сохранён итерационный CATIA-style алгоритм пересчёта геометрии.
- Сохранён Live Preview.
- Сохранено восстановление исходных Arrowhead Points.

### 🇬🇧 English

- Added content-aware placement reference.
- MText uses horizontal text center projected onto the landing line.
- Block / circular content uses the block content position.
- Preserved the iterative CATIA-style geometry recalculation algorithm.
- Preserved Live Preview.
- Preserved original Arrowhead restoration.

---

## v0.4

### 🇷🇺 Русский

- Добавлено выравнивание по полному центру содержимого для MText и блоков.
- Улучшено визуальное распределение аннотаций разной ширины.

### 🇬🇧 English

- Added full content-center alignment for MText and block content.
- Improved visual spacing for annotations with different widths.

---

## v0.3

### 🇷🇺 Русский

- Добавлен Live Preview при задании направления.
- Добавлено адаптивное ограничение частоты обновления для больших выборок.
- Добавлена отмена с восстановлением исходной геометрии.

### 🇬🇧 English

- Added Live Preview while specifying the alignment direction.
- Added adaptive preview throttling for large selections.
- Added cancellation with restoration of original geometry.

---

## v0.2

### 🇷🇺 Русский

- Восстановлен исходный итерационный алгоритм из CATIA VBA.
- Для каждой Target Point угол пересчитывается для каждого оставшегося MLeader.
- Используется распределение `N + 1`, поэтому аннотации занимают внутренние точки линии.

### 🇬🇧 English

- Reimplemented the original CATIA-style iterative algorithm.
- For every Target Point, the angle is recalculated for every remaining MLeader.
- Uses `N + 1` spacing so annotations occupy internal alignment points.

---

## v0.1

### 🇷🇺 Русский

- Первая экспериментальная AutoCAD / AutoLISP версия SmartAlign.

### 🇬🇧 English

- Initial AutoCAD / AutoLISP SmartAlign prototype.
