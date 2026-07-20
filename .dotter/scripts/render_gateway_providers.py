# /// script
# requires-python = ">=3.11"
# dependencies = ["jinja2"]
# ///
"""Render enterprise gateway providers for one consumer to stdout."""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from pathlib import Path

from jinja2 import Environment, StrictUndefined


REPO_ROOT = Path(__file__).resolve().parents[2]
CONSUMER_TEMPLATES = {
    'pi': REPO_ROOT / 'pi' / 'gateway-providers.json.j2',
    'opencode': REPO_ROOT / 'opencode' / 'gateway-providers.json.j2',
}


def load_local_variables() -> dict[str, object]:
    path = REPO_ROOT / '.dotter' / 'local.toml'
    try:
        with path.open('rb') as file:
            return tomllib.load(file).get('variables', {})
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"cannot read {path}: {error}") from error


def build_context() -> dict[str, object]:
    variables = load_local_variables()
    agent = variables.get('agent', {})
    if not isinstance(agent, dict):
        raise ValueError('variables.agent must be a table')
    clients = agent.get('enterprise_clients', {})
    deployments = agent.get('enterprise_deployments', {})
    if not isinstance(clients, dict) or not isinstance(deployments, dict):
        raise ValueError('enterprise_clients and enterprise_deployments must be tables')

    for name, deployment in deployments.items():
        if not isinstance(deployment, dict):
            raise ValueError(f"deployment {name} must be a table")
        models = deployment.get('models')
        if not isinstance(models, list) or not models:
            raise ValueError(f"deployment {name} requires a non-empty models array")
        for model in models:
            if not isinstance(model, dict) or not isinstance(model.get('id'), str):
                raise ValueError(f"deployment {name} contains an invalid model")
        deployment['name'] = name

    return {'clients': clients, 'deployments': list(deployments.values())}


def render(consumer: str) -> str:
    template_path = CONSUMER_TEMPLATES[consumer]
    environment = Environment(
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
        block_start_string='[%',
        block_end_string='%]',
        variable_start_string='[[',
        variable_end_string=']]',
    )
    template = environment.from_string(template_path.read_text(encoding='utf-8'))
    rendered = template.render(build_context())
    try:
        return json.dumps(json.loads(rendered), separators=(',', ':'))
    except json.JSONDecodeError as error:
        raise ValueError(f"{template_path} rendered invalid JSON: {error}") from error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('consumer', choices=CONSUMER_TEMPLATES)
    args = parser.parse_args()
    print(render(args.consumer))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"render_gateway_providers: {error}", file=sys.stderr)
        raise SystemExit(1) from error
