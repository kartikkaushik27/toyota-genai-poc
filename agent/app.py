"""
Minimal AgentCore Runtime-compliant agent.

Implements the AWS Bedrock AgentCore HTTP contract:
  - GET  /ping          -> health check
  - POST /invocations   -> agent interaction (calls Bedrock InvokeModel)

This is intentionally simple (no framework SDK) so the Toyota POC pipeline
demonstrates the exact wire contract AgentCore Runtime expects, matching the
"Build the agent container image" + "Inject BEDROCK_MODEL_ID,
BEDROCK_GUARDRAIL_ID, BEDROCK_GUARDRAIL_VERSION as environment variables"
requirements from the pipelines_requirements sheet.
"""
import json
import os
import time

import boto3
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()

BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
BEDROCK_GUARDRAIL_ID = os.environ.get("BEDROCK_GUARDRAIL_ID", "")
BEDROCK_GUARDRAIL_VERSION = os.environ.get("BEDROCK_GUARDRAIL_VERSION", "DRAFT")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)


@app.get("/ping")
def ping():
    return JSONResponse(status_code=200, content={"status": "Healthy"})


@app.post("/invocations")
async def invocations(request: Request):
    body = await request.json()
    prompt = body.get("prompt") or (body.get("input", {}) or {}).get("prompt", "")

    if not prompt:
        return JSONResponse(status_code=400, content={"error": "Missing 'prompt' in request body"})

    converse_kwargs = {
        "modelId": BEDROCK_MODEL_ID,
        "messages": [{"role": "user", "content": [{"text": prompt}]}],
    }

    if BEDROCK_GUARDRAIL_ID:
        converse_kwargs["guardrailConfig"] = {
            "guardrailIdentifier": BEDROCK_GUARDRAIL_ID,
            "guardrailVersion": BEDROCK_GUARDRAIL_VERSION,
        }

    try:
        response = bedrock.converse(**converse_kwargs)
        output_text = response["output"]["message"]["content"][0]["text"]
        return JSONResponse(
            status_code=200,
            content={
                "output": output_text,
                "modelId": BEDROCK_MODEL_ID,
                "timestamp": int(time.time()),
            },
        )
    except Exception as exc:  # noqa: BLE001 — surface Bedrock errors to caller for POC visibility
        return JSONResponse(status_code=500, content={"error": str(exc)})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
