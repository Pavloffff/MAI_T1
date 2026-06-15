# Домашнее задание №1

## Подготовил студент группы М8О-106СВ-21 Павлов Иван Дмитриевич


| Файл задания | Содержание | Решение |
|--------------|----------|---------|
| `hws/hw1.md` | Architectural Kata - сбор и анализ требований | [`HW_1_KATA_SOLUTION.md`](HW_1_KATA_SOLUTION.md) |
| `hws/hw1_practice.md` | Нагрузочное тестирование demo-app-1 | [`HW_1_SOLUTION.md`](HW_1_SOLUTION.md) |


---

## Структура папки

```
hw1/
├── README.md                    # этот файл
├── HW_1_SOLUTION.md             # отчёт: нагрузочное тестирование
├── HW_1_KATA_SOLUTION.md        # отчёт: architectural kata
├── backend/
│   ├── main.go                  # backend с доп. метриками (*)
│   └── METRICS.md               # описание новых метрик
├── k6/scripts/
│   ├── common.js                # общая логика 80/20 POST/GET
│   ├── storm.js                 # "Шторм": 1000 VU за 10 с
│   ├── wave.js                  # "Волна": 0 to 500 VU за 2 мин
│   └── custom-sawtooth.js       # "Пила": чередование read/write фаз
├── scripts/
│   ├── setup.ps1                # патч backend + docker compose up
│   └── run-load-tests.ps1       # запуск k6-сценариев
└── results/                     # сюда пишутся summary k6 (после запуска)
```
