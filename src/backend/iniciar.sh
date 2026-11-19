#!/bin/bash
cd ~/sistema-facturacion/backend
source venv/bin/activate
python3 actualizar_apigw.py
uvicorn main:app --host 0.0.0.0 --port 8000
