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
from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar

from jinja2 import Environment, StrictUndefined


REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_CATALOG_PATH = (
    REPO_ROOT / 'agent' / 'config' / 'enterprise_llm_gateway' / 'models.toml'
)
CONSUMER_TEMPLATES = {
    'pi': REPO_ROOT / 'pi' / 'gateway-providers.json.j2',
    'opencode': REPO_ROOT / 'opencode' / 'gateway-providers.json.j2',
}


def require_table(value: object, subject: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ValueError(f"{subject} must be a table")
    return value


def require_nonempty_string(value: object, subject: str) -> str:
    if not isinstance(value, str) or not (normalized := value.strip()):
        raise ValueError(f"{subject} must be a non-empty string")
    return normalized


def require_positive_int(value: object, subject: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{subject} must be a positive integer")
    return value


def reject_unknown_fields(
    table: dict[str, object],
    allowed: frozenset[str],
    subject: str,
) -> None:
    unknown = sorted(set(table) - allowed)
    if unknown:
        raise ValueError(f"{subject} has unknown fields: {', '.join(unknown)}")


@dataclass(frozen=True)
class Client:
    api_key: str

    _ALLOWED_FIELDS: ClassVar[frozenset[str]] = frozenset({'api_key'})

    @classmethod
    def from_table(cls, name: object, value: object) -> Client:
        client_name = require_nonempty_string(name, 'client name')
        subject = f"client {client_name}"
        table = require_table(value, subject)
        reject_unknown_fields(table, cls._ALLOWED_FIELDS, subject)
        return cls(
            api_key=require_nonempty_string(table.get('api_key'), f"{subject} api_key")
        )


@dataclass(frozen=True)
class Model:
    id: str
    name: str
    context_window: int
    max_tokens: int
    input: tuple[str, ...]
    reasoning_enabled: bool = False
    reasoning_levels: tuple[str, ...] = ()
    reasoning_format: str | None = None

    _ALLOWED_FIELDS: ClassVar[frozenset[str]] = frozenset(
        {
            'id',
            'name',
            'context_window',
            'max_tokens',
            'input',
            'reasoning',
            'reasoning_format',
        }
    )
    _SUPPORTED_MODALITIES: ClassVar[frozenset[str]] = frozenset({'text', 'image'})
    _THINKING_LEVELS: ClassVar[tuple[str, ...]] = (
        'off',
        'minimal',
        'low',
        'medium',
        'high',
        'xhigh',
        'max',
    )

    @classmethod
    def from_table(cls, deployment_name: str, index: int, value: object) -> Model:
        subject = f"deployment {deployment_name} model {index}"
        table = require_table(value, subject)
        reject_unknown_fields(table, cls._ALLOWED_FIELDS, subject)

        raw_input = table.get('input')
        if not isinstance(raw_input, (list, tuple)) or not raw_input:
            raise ValueError(f"{subject} input must be a non-empty array")
        input_modalities = tuple(raw_input)
        invalid_modalities = [
            modality
            for modality in input_modalities
            if not isinstance(modality, str)
            or modality not in cls._SUPPORTED_MODALITIES
        ]
        if invalid_modalities:
            raise ValueError(f"{subject} input contains unsupported modality")

        context_window = require_positive_int(
            table.get('context_window'),
            f"{subject} context_window",
        )
        max_tokens = require_positive_int(
            table.get('max_tokens'), f"{subject} max_tokens"
        )
        if max_tokens > context_window:
            raise ValueError(f"{subject} max_tokens must not exceed context_window")

        raw_reasoning = table.get('reasoning', False)
        if isinstance(raw_reasoning, bool):
            reasoning_enabled = raw_reasoning
            reasoning_levels = ()
        elif isinstance(raw_reasoning, list) and raw_reasoning:
            reasoning_levels = tuple(raw_reasoning)
            if any(
                not isinstance(level, str) or level not in cls._THINKING_LEVELS
                for level in reasoning_levels
            ) or len(set(reasoning_levels)) != len(reasoning_levels):
                raise ValueError(
                    f"{subject} reasoning must contain unique supported thinking levels"
                )
            reasoning_enabled = True
        else:
            raise ValueError(
                f"{subject} reasoning must be a boolean or non-empty array"
            )

        reasoning_format = table.get('reasoning_format')
        if reasoning_format is not None:
            reasoning_format = require_nonempty_string(
                reasoning_format,
                f"{subject} reasoning_format",
            )
            if not reasoning_enabled:
                raise ValueError(f"{subject} reasoning_format requires reasoning")

        return cls(
            id=require_nonempty_string(table.get('id'), f"{subject} id"),
            name=require_nonempty_string(table.get('name'), f"{subject} name"),
            context_window=context_window,
            max_tokens=max_tokens,
            input=input_modalities,
            reasoning_enabled=reasoning_enabled,
            reasoning_levels=reasoning_levels,
            reasoning_format=reasoning_format,
        )

    @property
    def thinking_level_map(self) -> dict[str, str | None]:
        if not self.reasoning_levels:
            return {}
        return {
            level: level if level in self.reasoning_levels else None
            for level in self._THINKING_LEVELS
        }


@dataclass(frozen=True)
class Deployment:
    name: str
    base_url: str
    models: tuple[Model, ...]

    _ALLOWED_FIELDS: ClassVar[frozenset[str]] = frozenset({'base_url'})

    @classmethod
    def from_table(
        cls,
        name: object,
        value: object,
        raw_models: object,
    ) -> Deployment:
        deployment_name = require_nonempty_string(name, 'deployment name')
        subject = f"deployment {deployment_name}"
        table = require_table(value, subject)
        reject_unknown_fields(table, cls._ALLOWED_FIELDS, subject)
        if not isinstance(raw_models, list) or not raw_models:
            raise ValueError(f"{subject} requires a non-empty models array")
        return cls(
            name=deployment_name,
            base_url=require_nonempty_string(
                table.get('base_url'), f"{subject} base_url"
            ),
            models=tuple(
                Model.from_table(deployment_name, index, model)
                for index, model in enumerate(raw_models)
            ),
        )


def load_local_variables() -> dict[str, object]:
    path = REPO_ROOT / '.dotter' / 'local.toml'
    try:
        with path.open('rb') as file:
            return tomllib.load(file).get('variables', {})
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"cannot read {path}: {error}") from error


def load_model_catalog() -> dict[str, list[object]]:
    try:
        with MODEL_CATALOG_PATH.open('rb') as file:
            catalog = require_table(tomllib.load(file), 'model catalog')
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ValueError(f"cannot read {MODEL_CATALOG_PATH}: {error}") from error

    schema_version = catalog.pop('schema_version', None)
    if schema_version != 1 or isinstance(schema_version, bool):
        raise ValueError('model catalog schema_version must be the integer 1')

    deployments: dict[str, list[object]] = {}
    for name, value in catalog.items():
        deployment_name = require_nonempty_string(name, 'model catalog deployment name')
        subject = f"model catalog deployment {deployment_name}"
        table = require_table(value, subject)
        reject_unknown_fields(table, frozenset({'models'}), subject)
        models = table.get('models')
        if not isinstance(models, list) or not models:
            raise ValueError(f"{subject} requires a non-empty models array")
        deployments[deployment_name] = models

    if not deployments:
        raise ValueError('model catalog requires at least one deployment')
    return deployments


def build_context() -> dict[str, object]:
    variables = load_local_variables()
    agent = variables.get('agent', {})
    agent = require_table(agent, 'variables.agent')
    clients = agent.get('enterprise_clients', {})
    deployments = agent.get('enterprise_deployments', {})
    if not isinstance(clients, dict) or not isinstance(deployments, dict):
        raise ValueError('enterprise_clients and enterprise_deployments must be tables')
    catalog = load_model_catalog()
    local_deployment_names = set(deployments)
    catalog_deployment_names = set(catalog)
    if local_deployment_names != catalog_deployment_names:
        missing = sorted(catalog_deployment_names - local_deployment_names)
        extra = sorted(local_deployment_names - catalog_deployment_names)
        details = [
            f"missing local settings: {', '.join(missing)}" if missing else '',
            f"missing catalog models: {', '.join(extra)}" if extra else '',
        ]
        raise ValueError(
            f"deployment names must match model catalog ({'; '.join(detail for detail in details if detail)})"
        )

    return {
        'clients': {
            require_nonempty_string(name, 'client name'): Client.from_table(
                name, client
            )
            for name, client in clients.items()
        },
        'deployments': [
            Deployment.from_table(name, deployment, catalog[name])
            for name, deployment in deployments.items()
        ],
    }


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
