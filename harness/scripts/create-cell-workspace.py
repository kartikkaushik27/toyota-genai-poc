#!/usr/bin/env python3
"""Create the Harness IaCM workspace for a cell.

One workspace per cell, because a workspace owns exactly one OpenTofu state.
The Provision Cell pipeline resolves its target workspace from the cell_name
input, so the workspace identifier MUST equal the cell name.

Harness validates the AWS connector when the workspace is saved, which is why
the connector is set here rather than being switched per pipeline run.

Usage:
    export HARNESS_API_KEY=pat....
    export HARNESS_ACCOUNT_ID=...
    ./create-cell-workspace.py --cell cell2 --region us-west-2 \
        --aws-connector aws_cell2
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("HARNESS_BASE_URL", "https://app.harness.io")


def call(method, path, api_key, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        headers={"x-api-key": api_key, "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cell", required=True, help="Cell name, e.g. cell2 — must match opentofu/cells/<cell>")
    ap.add_argument("--region", required=True, help="AWS region for the cell")
    ap.add_argument("--aws-connector", required=True, help="Harness AWS connector for the cell's account")
    ap.add_argument("--org", default=os.environ.get("HARNESS_ORG", "default"))
    ap.add_argument("--project", default=os.environ.get("HARNESS_PROJECT", "toyota_genai_full"))
    ap.add_argument("--repo", default="https://github.com/kartikkaushik27/toyota-genai-poc")
    ap.add_argument("--repo-connector", default="github_full")
    ap.add_argument("--branch", default="main")
    args = ap.parse_args()

    api_key = os.environ.get("HARNESS_API_KEY")
    account = os.environ.get("HARNESS_ACCOUNT_ID")
    if not api_key or not account:
        sys.exit("HARNESS_API_KEY and HARNESS_ACCOUNT_ID must be set")

    payload = {
        "identifier": args.cell,
        "name": args.cell.replace("_", " ").replace("-", " ").title(),
        "description": f"{args.cell} provisioning workspace — one workspace (one state) per cell.",
        "provisioner": "opentofu",
        "provisioner_version": "latest",
        "repository": args.repo,
        "repository_branch": args.branch,
        "repository_connector": args.repo_connector,
        "repository_path": f"opentofu/cells/{args.cell}",
        "cost_estimation_enabled": False,
        "provider_connector": args.aws_connector,
        # Values arrive from the Provision Cell pipeline at run time.
        "terraform_variables": {
            "cell_name": {"key": "cell_name", "value": "<+pipeline.variables.cell_name>", "value_type": "string"},
            "aws_region": {"key": "aws_region", "value": "<+pipeline.variables.aws_region>", "value_type": "string"},
        },
        "environment_variables": {
            "AWS_ACCESS_KEY_ID": {"key": "AWS_ACCESS_KEY_ID", "value": "aws_access_key_id", "value_type": "secret"},
            "AWS_SECRET_ACCESS_KEY": {"key": "AWS_SECRET_ACCESS_KEY", "value": "aws_secret_access_key", "value_type": "secret"},
            "AWS_SESSION_TOKEN": {"key": "AWS_SESSION_TOKEN", "value": "aws_session_token", "value_type": "secret"},
            "AWS_DEFAULT_REGION": {"key": "AWS_DEFAULT_REGION", "value": "<+pipeline.variables.aws_region>", "value_type": "string"},
        },
    }

    status, body = call(
        "POST",
        f"/iacm/api/orgs/{args.org}/projects/{args.project}/workspaces?accountIdentifier={account}",
        api_key,
        payload,
    )
    if status >= 300:
        sys.exit(f"Failed to create workspace ({status}): {body}")

    print(f"Created workspace '{args.cell}' -> opentofu/cells/{args.cell} (connector {args.aws_connector})")
    print(f"Now run the Provision Cell pipeline with cell_name={args.cell}, "
          f"aws_region={args.region}, aws_connector={args.aws_connector}")


if __name__ == "__main__":
    main()
