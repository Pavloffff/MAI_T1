# Запуск traffic-generator.py (требуется psycopg2)
pip install psycopg2-binary -q
$Script = Join-Path $PSScriptRoot "..\traffic-generator.py"
python $Script
