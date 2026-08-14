from __future__ import annotations

import json
import pathlib

from services.research_worker.src.search.fixture_provider import (
    FixtureCatalogEntry,
    fixture_provider_a,
    fixture_provider_b,
)
from services.research_worker.test.schema_validator import ContractSchemaValidator

ROOT = pathlib.Path(__file__).resolve().parents[3]
FIXTURE_PATH = ROOT / "services/research_worker/test/fixtures/p4_001_search_provider/contract_cases.json"
SCHEMA_PATHS = {
    "request": ROOT / "schemas/web_search_request.v1.json",
    "page": ROOT / "schemas/web_search_page.v1.json",
    "error": ROOT / "schemas/web_search_error.v1.json",
}


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_contract_state():
    fixture = load_json(FIXTURE_PATH)
    schemas = {name: load_json(path) for name, path in SCHEMA_PATHS.items()}
    validators = {
        name: ContractSchemaValidator(schema) for name, schema in schemas.items()
    }
    entries = tuple(
        FixtureCatalogEntry(
            title=item["title"],
            url=item["url"],
            snippet=item["snippet"],
            published_at=item["publishedAt"],
            language=item["language"],
            country=item["country"],
            provider_metadata=item["providerMetadata"],
        )
        for item in fixture["catalog"]
    )
    providers = {
        "fixture_alpha": fixture_provider_a(entries),
        "fixture_beta": fixture_provider_b(entries),
    }
    return fixture, schemas, validators, providers
