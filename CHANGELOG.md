# Changelog

🇷🇺 Русское описание и 🇬🇧 English description приведены для каждого релиза.

---

## MLeaderSmartAlign Perimeter v0.1

### 🇷🇺 Русский

- Добавлен новый режим автоматического распределения `MULTILEADER` по периметру параллелограмма.
- Добавлен файл `MLeaderSmartAlign_Perimeter_v01_fix1.lsp`.
- Добавлены команды `MSAP` и `MLeaderSmartAlignPerimeter`.
- Параллелограмм задаётся тремя пользовательскими точками `P1 → P2 → P3`.
- Четвёртая вершина рассчитывается автоматически: `P4 = P1 + (P3 - P2)`.
- Добавлено интерактивное построение первой и второй стороны с временной пунктирной графикой.
- После фиксации `P3` автоматически отображаются четыре стороны параллелограмма и две диагонали.
- Диагонали делят область на четыре треугольных сектора.
- Каждый MLeader классифицируется по исходной representative Arrow Point.
- Каждая область назначается соответствующей стороне:
  - `P1-P2-C → P1-P2`
  - `P2-P3-C → P2-P3`
  - `P3-P4-C → P3-P4`
  - `P4-P1-C → P4-P1`
- Точки на границе или вне параллелограмма назначаются ближайшей стороне.
- Для каждой стороны повторно используется проверенный итерационный алгоритм из `MLeaderSmartAlign v0.5`.
- MLeader размещаются пошагово, один за другим.
- Исходные arrowhead points сохраняются.
- Временная геометрия не записывается в DWG и исчезает после завершения команды.
- Добавлена демонстрация `images/MLeaderSmartAlign_Perimeter.gif`.
- Исправлена ошибка AutoLISP `incorrect object to bind: T`: локальные переменные `t` переименованы в безопасные `ratio` / `param`.
- Perimeter использует функции из `MLeaderSmartAlign_v05.lsp` и требует загрузки базового файла.

### 🇬🇧 English

- Added a new mode for automatically distributing `MULTILEADER` objects around a parallelogram perimeter.
- Added `MLeaderSmartAlign_Perimeter_v01_fix1.lsp`.
- Added commands `MSAP` and `MLeaderSmartAlignPerimeter`.
- The parallelogram is defined by three user-picked points: `P1 → P2 → P3`.
- The fourth vertex is calculated automatically: `P4 = P1 + (P3 - P2)`.
- Added interactive rubber-band creation of the first and second sides.
- After `P3` is fixed, four perimeter sides and two diagonals are displayed automatically.
- The diagonals divide the parallelogram into four triangular regions.
- Each MLeader is classified using its original representative Arrow Point.
- Each region is assigned to its corresponding side:
  - `P1-P2-C → P1-P2`
  - `P2-P3-C → P2-P3`
  - `P3-P4-C → P3-P4`
  - `P4-P1-C → P4-P1`
- Boundary or outside points are assigned to the nearest perimeter side.
- Every side group reuses the proven iterative algorithm from `MLeaderSmartAlign v0.5`.
- MLeaders are placed step by step, one at a time.
- Original arrowhead points remain preserved.
- Temporary helper geometry is display-only and disappears when the command finishes.
- Added demo `images/MLeaderSmartAlign_Perimeter.gif`.
- Fixed AutoLISP error `incorrect object to bind: T`: local/formal variables named `t` were renamed to safe names such as `ratio` / `param`.
- Perimeter reuses functions from `MLeaderSmartAlign_v05.lsp` and therefore requires the base file to be loaded.

---

## v0.5

### 🇷🇺 Русский

- Добавлена content-aware точка размещения.
- MText использует горизонтальный центр текста, спроецированный на landing line.
- Блочное / круглое содержимое использует позицию блока.
- Сохранён итерационный CATIA-style алгоритм пересчёта геометрии.
- Сохранён Live Preview.
- Сохранено восстановление исходных arrowhead points.

### 🇬🇧 English

- Added content-aware placement reference.
- MText uses horizontal text center projected onto the landing line.
- Block / circular content uses the block content position.
- Preserved the iterative CATIA-style geometry recalculation algorithm.
- Preserved Live Preview.
- Preserved original arrowhead restoration.

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

- Added Live Preview while specifying alignment direction.
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
- For every target position, recalculates the angle for every remaining MLeader.
- Uses `N + 1` spacing so annotations occupy internal alignment points.

---

## v0.1

### 🇷🇺 Русский

- Первая экспериментальная AutoCAD / AutoLISP версия SmartAlign.

### 🇬🇧 English

- Initial AutoCAD / AutoLISP SmartAlign prototype.
