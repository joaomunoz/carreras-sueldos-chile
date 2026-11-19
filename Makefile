# Makefile
#
# Reproduce el proyecto completo con un comando. Requiere PostgreSQL en marcha, la variable
# PGDATABASE (p. ej. export PGDATABASE=carreras_sueldos) y Python 3 con psycopg.
#
#   make todo    base de datos → datos.json → index.html
#   make base    src/BD/build.py: raw + modelo + analytics + controles qa (una transacción)
#   make datos   src/Analisis/exportar.py: docs/datos.json (no exporta si algún control falla)
#   make web     src/Web/construir.py: docs/index.html autónomo (no necesita la base) y el bloque
#                "Hallazgos" y el conteo de controles del README, desde datos.json
#
# Las metas son .PHONY a propósito: cada paso tiene sus propias verificaciones y es barato
# (~10 s el build); rastrear dependencias por fecha de archivo daría falsos "al día".

.PHONY: todo base datos web
# El orden importa (base → datos → web): nunca en paralelo, aunque se llame con make -j.
.NOTPARALLEL:

todo: base datos web

base:
	python3 src/BD/build.py

datos:
	python3 src/Analisis/exportar.py

web:
	python3 src/Web/construir.py
