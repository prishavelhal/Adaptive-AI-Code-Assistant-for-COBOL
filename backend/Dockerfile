FROM python:3.11-slim

WORKDIR /app

# install dependencies first so Docker caches this layer
# and doesn't reinstall every time  code changes
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]