FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/ ./api/

# UI build copied in CI/CD or mounted in dev
# COPY ui/dist/ ./ui/dist/

EXPOSE 8889

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8889"]
