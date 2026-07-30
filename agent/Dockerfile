# AgentCore Runtime requires linux/arm64 — build with:
#   docker buildx build --platform linux/arm64 -t <ecr-repo>:<tag> .
FROM --platform=linux/arm64 python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["python", "app.py"]
