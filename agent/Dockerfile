# NOTE: AgentCore Runtime requires linux/arm64 in production. This POC builds
# natively on the Harness Cloud amd64 runner (no QEMU/buildx available without
# privileged mode) to prove out the CI/CD pipeline mechanics end-to-end. For a
# real deployment, build with:
#   docker buildx build --platform linux/arm64 -t <ecr-repo>:<tag> --push .
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["python", "app.py"]
