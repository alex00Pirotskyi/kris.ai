// GENERATED FILE. DO NOT EDIT.
// Source: tool/generate_prompt_studio_contracts.py

const promptStudioContractDigest =
    '4f65d0e57ee86b58b26223970c8fbfda243256a47689ce83568df88be042500a';
const promptStudioSpecificationSchemaVersion = '2.0.0';
const promptStudioTaskPlanSchemaVersion = '2.0.0';
const promptStudioEvaluationSchemaVersion = '1.0.0';
const promptStudioCompilerVersion = '1.0.0';

// product_specification.v2.json
const productSpecificationV2SchemaJson = r'''{
  "$id": "https://kristin.local/schemas/product_specification.v2.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties": false,
  "properties": {
    "acceptanceCriteria": {
      "items": {
        "additionalProperties": false,
        "properties": {
          "evidenceValidatorIds": {
            "items": {
              "type": "string"
            },
            "maxItems": 20,
            "minItems": 1,
            "type": "array",
            "uniqueItems": true
          },
          "id": {
            "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
            "type": "string"
          },
          "requirementIds": {
            "items": {
              "type": "string"
            },
            "maxItems": 50,
            "type": "array",
            "uniqueItems": true
          },
          "statement": {
            "maxLength": 4000,
            "minLength": 8,
            "type": "string"
          }
        },
        "required": [
          "id",
          "statement",
          "evidenceValidatorIds"
        ],
        "type": "object"
      },
      "maxItems": 200,
      "minItems": 1,
      "type": "array"
    },
    "artifacts": {
      "items": {
        "additionalProperties": false,
        "properties": {
          "description": {
            "maxLength": 2000,
            "minLength": 4,
            "type": "string"
          },
          "id": {
            "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
            "type": "string"
          },
          "path": {
            "format": "project-relative-path",
            "maxLength": 4096,
            "minLength": 1,
            "type": "string"
          },
          "required": {
            "type": "boolean"
          },
          "sensitivity": {
            "enum": [
              "public",
              "internal",
              "confidential",
              "secret"
            ]
          },
          "type": {
            "enum": [
              "source",
              "document",
              "spreadsheet",
              "presentation",
              "image",
              "archive",
              "binary",
              "api",
              "website",
              "configuration",
              "test_report",
              "package",
              "other"
            ]
          },
          "validators": {
            "items": {
              "additionalProperties": false,
              "properties": {
                "config": {
                  "additionalProperties": true,
                  "type": "object"
                },
                "description": {
                  "maxLength": 2000,
                  "type": "string"
                },
                "deterministic": {
                  "type": "boolean"
                },
                "id": {
                  "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
                  "type": "string"
                },
                "kind": {
                  "enum": [
                    "file_exists",
                    "non_empty",
                    "sha256_stable",
                    "text_contains",
                    "json_schema",
                    "command_exit_zero",
                    "test_passes",
                    "archive_manifest",
                    "reopen",
                    "manual_review"
                  ]
                }
              },
              "required": [
                "id",
                "kind",
                "deterministic",
                "config"
              ],
              "type": "object"
            },
            "maxItems": 20,
            "minItems": 1,
            "type": "array"
          }
        },
        "required": [
          "id",
          "type",
          "description",
          "required",
          "sensitivity",
          "validators"
        ],
        "type": "object"
      },
      "maxItems": 200,
      "minItems": 1,
      "type": "array"
    },
    "assumptions": {
      "items": {
        "maxLength": 2000,
        "minLength": 3,
        "type": "string"
      },
      "maxItems": 100,
      "type": "array"
    },
    "clarificationQuestions": {
      "items": {
        "maxLength": 2000,
        "minLength": 3,
        "type": "string"
      },
      "maxItems": 50,
      "type": "array"
    },
    "dataPolicy": {
      "additionalProperties": false,
      "properties": {
        "allowNetworkResearch": {
          "default": false,
          "type": "boolean"
        },
        "allowSecretUse": {
          "default": false,
          "type": "boolean"
        },
        "allowedProviders": {
          "items": {
            "maxLength": 200,
            "minLength": 1,
            "type": "string"
          },
          "maxItems": 20,
          "type": "array",
          "uniqueItems": true
        },
        "localOnly": {
          "type": "boolean"
        },
        "retention": {
          "enum": [
            "session",
            "project",
            "user_managed",
            "none"
          ]
        },
        "sensitivity": {
          "enum": [
            "public",
            "internal",
            "confidential",
            "secret"
          ]
        }
      },
      "required": [
        "localOnly",
        "sensitivity",
        "allowedProviders",
        "retention"
      ],
      "type": "object"
    },
    "deploymentBoundary": {
      "additionalProperties": false,
      "properties": {
        "approvalRequired": {
          "type": "boolean"
        },
        "mode": {
          "enum": [
            "none",
            "local_preview",
            "package_only",
            "external_manual",
            "external_automated"
          ]
        },
        "target": {
          "maxLength": 500,
          "type": [
            "string",
            "null"
          ]
        }
      },
      "required": [
        "mode",
        "target",
        "approvalRequired"
      ],
      "type": "object"
    },
    "excludedScope": {
      "items": {
        "maxLength": 2000,
        "minLength": 3,
        "type": "string"
      },
      "maxItems": 100,
      "type": "array"
    },
    "functionalRequirements": {
      "items": {
        "additionalProperties": false,
        "properties": {
          "id": {
            "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
            "type": "string"
          },
          "priority": {
            "enum": [
              "must",
              "should",
              "could",
              "wont"
            ]
          },
          "source": {
            "maxLength": 1000,
            "type": "string"
          },
          "statement": {
            "maxLength": 4000,
            "minLength": 8,
            "type": "string"
          }
        },
        "required": [
          "id",
          "statement",
          "priority"
        ],
        "type": "object"
      },
      "maxItems": 200,
      "minItems": 1,
      "type": "array"
    },
    "id": {
      "pattern": "^spec_[a-z0-9][a-z0-9_.-]{2,63}$",
      "type": "string"
    },
    "metadata": {
      "additionalProperties": true,
      "type": "object"
    },
    "nonFunctionalRequirements": {
      "items": {
        "additionalProperties": false,
        "properties": {
          "id": {
            "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
            "type": "string"
          },
          "priority": {
            "enum": [
              "must",
              "should",
              "could",
              "wont"
            ]
          },
          "source": {
            "maxLength": 1000,
            "type": "string"
          },
          "statement": {
            "maxLength": 4000,
            "minLength": 8,
            "type": "string"
          }
        },
        "required": [
          "id",
          "statement",
          "priority"
        ],
        "type": "object"
      },
      "maxItems": 100,
      "type": "array"
    },
    "problemStatement": {
      "maxLength": 10000,
      "minLength": 20,
      "type": "string"
    },
    "riskClassification": {
      "enum": [
        "low",
        "medium",
        "high",
        "critical"
      ]
    },
    "schemaVersion": {
      "const": "2.0.0"
    },
    "targetPlatforms": {
      "items": {
        "maxLength": 200,
        "minLength": 2,
        "type": "string"
      },
      "maxItems": 20,
      "minItems": 1,
      "type": "array",
      "uniqueItems": true
    },
    "targetUsers": {
      "items": {
        "maxLength": 500,
        "minLength": 2,
        "type": "string"
      },
      "maxItems": 20,
      "minItems": 1,
      "type": "array",
      "uniqueItems": true
    },
    "testStrategy": {
      "items": {
        "maxLength": 2000,
        "minLength": 4,
        "type": "string"
      },
      "maxItems": 100,
      "minItems": 1,
      "type": "array"
    },
    "title": {
      "maxLength": 200,
      "minLength": 3,
      "type": "string"
    }
  },
  "required": [
    "schemaVersion",
    "id",
    "title",
    "problemStatement",
    "targetUsers",
    "functionalRequirements",
    "nonFunctionalRequirements",
    "excludedScope",
    "assumptions",
    "clarificationQuestions",
    "targetPlatforms",
    "dataPolicy",
    "artifacts",
    "acceptanceCriteria",
    "testStrategy",
    "deploymentBoundary",
    "riskClassification"
  ],
  "title": "Kristin Product Specification v2",
  "type": "object"
}
''';

// task_plan.v2.json
const taskPlanV2SchemaJson = r'''{
  "$id": "https://kristin.local/schemas/task_plan.v2.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties": false,
  "properties": {
    "id": {
      "pattern": "^plan_[a-z0-9][a-z0-9_.-]{2,63}$",
      "type": "string"
    },
    "localOnly": {
      "type": "boolean"
    },
    "metadata": {
      "additionalProperties": true,
      "type": "object"
    },
    "promptVersionId": {
      "maxLength": 200,
      "minLength": 1,
      "type": "string"
    },
    "rationale": {
      "maxLength": 8000,
      "minLength": 8,
      "type": "string"
    },
    "schemaVersion": {
      "const": "2.0.0"
    },
    "specificationId": {
      "pattern": "^spec_[a-z0-9][a-z0-9_.-]{2,63}$",
      "type": "string"
    },
    "tasks": {
      "items": {
        "additionalProperties": false,
        "properties": {
          "acceptanceCriteria": {
            "items": {
              "additionalProperties": false,
              "properties": {
                "evidenceValidatorIds": {
                  "items": {
                    "type": "string"
                  },
                  "maxItems": 20,
                  "minItems": 1,
                  "type": "array",
                  "uniqueItems": true
                },
                "id": {
                  "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
                  "type": "string"
                },
                "requirementIds": {
                  "items": {
                    "type": "string"
                  },
                  "maxItems": 50,
                  "type": "array",
                  "uniqueItems": true
                },
                "statement": {
                  "maxLength": 4000,
                  "minLength": 8,
                  "type": "string"
                }
              },
              "required": [
                "id",
                "statement",
                "evidenceValidatorIds"
              ],
              "type": "object"
            },
            "maxItems": 50,
            "type": "array"
          },
          "allowedTools": {
            "items": {
              "pattern": "^[a-z][a-z0-9_]{2,63}$",
              "type": "string"
            },
            "maxItems": 30,
            "type": "array",
            "uniqueItems": true
          },
          "budgets": {
            "additionalProperties": false,
            "properties": {
              "modelTurns": {
                "maximum": 100,
                "minimum": 0,
                "type": "integer"
              },
              "outputBytes": {
                "maximum": 100000000,
                "minimum": 0,
                "type": "integer"
              },
              "toolCalls": {
                "maximum": 500,
                "minimum": 0,
                "type": "integer"
              }
            },
            "required": [
              "modelTurns",
              "toolCalls",
              "outputBytes"
            ],
            "type": "object"
          },
          "complexity": {
            "maximum": 10,
            "minimum": 1,
            "type": "integer"
          },
          "dataBoundary": {
            "enum": [
              "project",
              "local",
              "network",
              "external",
              "secret"
            ]
          },
          "dependencies": {
            "items": {
              "pattern": "^task_[0-9]{3}$",
              "type": "string"
            },
            "maxItems": 100,
            "type": "array",
            "uniqueItems": true
          },
          "effortPoints": {
            "enum": [
              1,
              2,
              3,
              5,
              8,
              13
            ]
          },
          "enabled": {
            "type": "boolean"
          },
          "estimateConfidence": {
            "maximum": 1,
            "minimum": 0,
            "type": "number"
          },
          "id": {
            "pattern": "^task_[0-9]{3}$",
            "type": "string"
          },
          "inputArtifacts": {
            "items": {
              "type": "string"
            },
            "maxItems": 100,
            "type": "array",
            "uniqueItems": true
          },
          "instructions": {
            "maxLength": 12000,
            "minLength": 8,
            "type": "string"
          },
          "manual": {
            "type": "boolean"
          },
          "objective": {
            "maxLength": 4000,
            "minLength": 8,
            "type": "string"
          },
          "order": {
            "maximum": 1000,
            "minimum": 1,
            "type": "integer"
          },
          "outputArtifacts": {
            "items": {
              "additionalProperties": false,
              "properties": {
                "description": {
                  "maxLength": 2000,
                  "minLength": 4,
                  "type": "string"
                },
                "id": {
                  "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
                  "type": "string"
                },
                "path": {
                  "format": "project-relative-path",
                  "maxLength": 4096,
                  "minLength": 1,
                  "type": "string"
                },
                "required": {
                  "type": "boolean"
                },
                "sensitivity": {
                  "enum": [
                    "public",
                    "internal",
                    "confidential",
                    "secret"
                  ]
                },
                "type": {
                  "enum": [
                    "source",
                    "document",
                    "spreadsheet",
                    "presentation",
                    "image",
                    "archive",
                    "binary",
                    "api",
                    "website",
                    "configuration",
                    "test_report",
                    "package",
                    "other"
                  ]
                },
                "validators": {
                  "items": {
                    "additionalProperties": false,
                    "properties": {
                      "config": {
                        "additionalProperties": true,
                        "type": "object"
                      },
                      "description": {
                        "maxLength": 2000,
                        "type": "string"
                      },
                      "deterministic": {
                        "type": "boolean"
                      },
                      "id": {
                        "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
                        "type": "string"
                      },
                      "kind": {
                        "enum": [
                          "file_exists",
                          "non_empty",
                          "sha256_stable",
                          "text_contains",
                          "json_schema",
                          "command_exit_zero",
                          "test_passes",
                          "archive_manifest",
                          "reopen",
                          "manual_review"
                        ]
                      }
                    },
                    "required": [
                      "id",
                      "kind",
                      "deterministic",
                      "config"
                    ],
                    "type": "object"
                  },
                  "maxItems": 20,
                  "minItems": 1,
                  "type": "array"
                }
              },
              "required": [
                "id",
                "type",
                "description",
                "required",
                "sensitivity",
                "validators"
              ],
              "type": "object"
            },
            "maxItems": 50,
            "type": "array"
          },
          "parentId": {
            "pattern": "^task_[0-9]{3}$",
            "type": [
              "string",
              "null"
            ]
          },
          "phase": {
            "maxLength": 120,
            "minLength": 2,
            "type": "string"
          },
          "requiredCapabilities": {
            "items": {
              "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
              "type": "string"
            },
            "maxItems": 30,
            "type": "array",
            "uniqueItems": true
          },
          "retryPolicy": {
            "additionalProperties": false,
            "properties": {
              "maxAttempts": {
                "maximum": 5,
                "minimum": 1,
                "type": "integer"
              },
              "retryableClasses": {
                "items": {
                  "enum": [
                    "provider_transient",
                    "schema_repair",
                    "tool_input_repair",
                    "project_state_conflict",
                    "verification_failure",
                    "resource_unavailable"
                  ]
                },
                "maxItems": 20,
                "type": "array",
                "uniqueItems": true
              }
            },
            "required": [
              "maxAttempts",
              "retryableClasses"
            ],
            "type": "object"
          },
          "risk": {
            "enum": [
              "low",
              "medium",
              "high",
              "critical"
            ]
          },
          "stopPolicy": {
            "additionalProperties": false,
            "properties": {
              "maxNonProgressTurns": {
                "maximum": 10,
                "minimum": 0,
                "type": "integer"
              },
              "onAmbiguousSideEffect": {
                "enum": [
                  "stop",
                  "ask_user"
                ]
              },
              "onPolicyRejection": {
                "const": "stop"
              }
            },
            "required": [
              "maxNonProgressTurns",
              "onPolicyRejection",
              "onAmbiguousSideEffect"
            ],
            "type": "object"
          },
          "targetScope": {
            "enum": [
              "project",
              "host_application"
            ]
          },
          "taskType": {
            "enum": [
              "analysis",
              "research",
              "design",
              "implementation",
              "migration",
              "documentation",
              "verification",
              "test",
              "build",
              "run",
              "deployment",
              "approval",
              "manual"
            ]
          },
          "title": {
            "maxLength": 240,
            "minLength": 3,
            "type": "string"
          },
          "uncertainty": {
            "enum": [
              "low",
              "medium",
              "high"
            ]
          },
          "verification": {
            "items": {
              "additionalProperties": false,
              "properties": {
                "config": {
                  "additionalProperties": true,
                  "type": "object"
                },
                "description": {
                  "maxLength": 2000,
                  "type": "string"
                },
                "deterministic": {
                  "type": "boolean"
                },
                "id": {
                  "pattern": "^[a-z][a-z0-9_.-]{2,63}$",
                  "type": "string"
                },
                "kind": {
                  "enum": [
                    "file_exists",
                    "non_empty",
                    "sha256_stable",
                    "text_contains",
                    "json_schema",
                    "command_exit_zero",
                    "test_passes",
                    "archive_manifest",
                    "reopen",
                    "manual_review"
                  ]
                }
              },
              "required": [
                "id",
                "kind",
                "deterministic",
                "config"
              ],
              "type": "object"
            },
            "maxItems": 50,
            "type": "array"
          }
        },
        "required": [
          "id",
          "parentId",
          "phase",
          "order",
          "title",
          "objective",
          "instructions",
          "taskType",
          "dependencies",
          "requiredCapabilities",
          "allowedTools",
          "inputArtifacts",
          "outputArtifacts",
          "acceptanceCriteria",
          "verification",
          "dataBoundary",
          "targetScope",
          "complexity",
          "effortPoints",
          "uncertainty",
          "risk",
          "estimateConfidence",
          "budgets",
          "retryPolicy",
          "stopPolicy",
          "enabled",
          "manual"
        ],
        "type": "object"
      },
      "maxItems": 100,
      "minItems": 1,
      "type": "array"
    },
    "title": {
      "maxLength": 240,
      "minLength": 3,
      "type": "string"
    }
  },
  "required": [
    "schemaVersion",
    "id",
    "specificationId",
    "promptVersionId",
    "title",
    "rationale",
    "localOnly",
    "tasks"
  ],
  "title": "Kristin Task Plan v2",
  "type": "object"
}
''';

// prompt_evaluation_dataset.v1.json
const promptEvaluationDatasetV1SchemaJson = r'''{
  "$id": "https://kristin.local/schemas/prompt_evaluation_dataset.v1.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties": false,
  "properties": {
    "cases": {
      "items": {
        "additionalProperties": false,
        "properties": {
          "expectedMode": {
            "enum": [
              "ask",
              "analyze",
              "plan",
              "build",
              "fix",
              "review",
              "run"
            ]
          },
          "forbiddenTerms": {
            "items": {
              "maxLength": 200,
              "minLength": 1,
              "type": "string"
            },
            "maxItems": 50,
            "type": "array",
            "uniqueItems": true
          },
          "id": {
            "pattern": "^case_[a-z0-9][a-z0-9_.-]{2,63}$",
            "type": "string"
          },
          "input": {
            "maxLength": 10000,
            "minLength": 1,
            "type": "string"
          },
          "requiredCriterionTerms": {
            "items": {
              "maxLength": 200,
              "minLength": 1,
              "type": "string"
            },
            "maxItems": 50,
            "type": "array",
            "uniqueItems": true
          },
          "requiredTerms": {
            "items": {
              "maxLength": 200,
              "minLength": 1,
              "type": "string"
            },
            "maxItems": 50,
            "type": "array",
            "uniqueItems": true
          },
          "requiredVariables": {
            "items": {
              "maxLength": 100,
              "minLength": 1,
              "type": "string"
            },
            "maxItems": 50,
            "type": "array",
            "uniqueItems": true
          },
          "tags": {
            "items": {
              "maxLength": 100,
              "minLength": 1,
              "type": "string"
            },
            "maxItems": 30,
            "type": "array",
            "uniqueItems": true
          },
          "variables": {
            "additionalProperties": {
              "type": "string"
            },
            "type": "object"
          },
          "weight": {
            "exclusiveMinimum": 0,
            "maximum": 100,
            "type": "number"
          }
        },
        "required": [
          "id",
          "input",
          "variables",
          "requiredTerms",
          "forbiddenTerms",
          "requiredVariables",
          "requiredCriterionTerms",
          "expectedMode",
          "weight",
          "tags"
        ],
        "type": "object"
      },
      "maxItems": 200,
      "minItems": 1,
      "type": "array"
    },
    "id": {
      "pattern": "^eval_[a-z0-9][a-z0-9_.-]{2,63}$",
      "type": "string"
    },
    "promptId": {
      "maxLength": 200,
      "minLength": 1,
      "type": "string"
    },
    "schemaVersion": {
      "const": "1.0.0"
    },
    "title": {
      "maxLength": 240,
      "minLength": 3,
      "type": "string"
    }
  },
  "required": [
    "schemaVersion",
    "id",
    "title",
    "promptId",
    "cases"
  ],
  "title": "Kristin Prompt Evaluation Dataset v1",
  "type": "object"
}
''';

// plan_capability_catalog.v1.json
const planCapabilityCatalogV1Json = r'''{
  "$id": "https://kristin.local/schemas/plan_capability_catalog.v1.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "capabilities": [
    {
      "mutation": false,
      "name": "project.inspect",
      "network": false,
      "requiresSandbox": false,
      "tools": [
        "list_directory",
        "read_file",
        "inspect_file",
        "search_text",
        "index_project",
        "index_search"
      ]
    },
    {
      "mutation": true,
      "name": "project.mutate",
      "network": false,
      "requiresSandbox": false,
      "tools": [
        "write_file",
        "write_binary_file",
        "replace_text",
        "apply_patch",
        "delete_file"
      ]
    },
    {
      "mutation": false,
      "name": "project.verify",
      "network": false,
      "requiresSandbox": true,
      "tools": [
        "read_file",
        "inspect_file",
        "search_text",
        "run_command",
        "verify_project"
      ]
    },
    {
      "mutation": false,
      "name": "process.execute",
      "network": false,
      "requiresSandbox": true,
      "tools": [
        "run_command"
      ]
    },
    {
      "mutation": false,
      "name": "process.manage",
      "network": false,
      "requiresSandbox": true,
      "tools": [
        "start_process",
        "process_status",
        "stop_process"
      ]
    },
    {
      "mutation": false,
      "name": "git.inspect",
      "network": false,
      "requiresSandbox": false,
      "tools": [
        "git_status",
        "git_diff"
      ]
    },
    {
      "mutation": false,
      "name": "knowledge.retrieve",
      "network": false,
      "requiresSandbox": false,
      "tools": [
        "knowledge_search"
      ]
    },
    {
      "mutation": false,
      "name": "research.network",
      "network": true,
      "requiresSandbox": true,
      "tools": [
        "research_fetch",
        "research_search"
      ]
    },
    {
      "mutation": true,
      "name": "deployment.package",
      "network": false,
      "requiresSandbox": true,
      "tools": [
        "package_deployment"
      ]
    },
    {
      "mutation": false,
      "name": "external.mcp",
      "network": true,
      "requiresSandbox": true,
      "tools": [
        "mcp_call"
      ]
    },
    {
      "mutation": false,
      "name": "human.approval",
      "network": false,
      "requiresSandbox": false,
      "tools": []
    }
  ],
  "catalogVersion": "1.0.0",
  "taskTypeDefaults": {
    "analysis": [
      "project.inspect"
    ],
    "approval": [
      "human.approval"
    ],
    "build": [
      "project.inspect",
      "project.verify"
    ],
    "deployment": [
      "deployment.package"
    ],
    "design": [
      "project.inspect",
      "project.mutate"
    ],
    "documentation": [
      "project.inspect",
      "project.mutate"
    ],
    "implementation": [
      "project.inspect",
      "project.mutate"
    ],
    "manual": [
      "human.approval"
    ],
    "migration": [
      "project.inspect",
      "project.mutate"
    ],
    "research": [
      "knowledge.retrieve"
    ],
    "run": [
      "process.manage"
    ],
    "test": [
      "project.inspect",
      "project.verify"
    ],
    "verification": [
      "project.inspect",
      "project.verify"
    ]
  },
  "validatorCapabilities": {
    "archive_manifest": "project.inspect",
    "command_exit_zero": "project.verify",
    "file_exists": "project.inspect",
    "json_schema": "project.inspect",
    "manual_review": "human.approval",
    "non_empty": "project.inspect",
    "reopen": "project.inspect",
    "sha256_stable": "project.inspect",
    "test_passes": "project.verify",
    "text_contains": "project.inspect"
  }
}
''';

// plan_compilation_report.v1.json
const planCompilationReportV1SchemaJson = r'''{
  "$id": "https://kristin.local/schemas/plan_compilation_report.v1.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "additionalProperties": false,
  "properties": {
    "compiledTasks": {
      "items": {
        "additionalProperties": true,
        "type": "object"
      },
      "type": "array"
    },
    "compilerVersion": {
      "type": "string"
    },
    "executable": {
      "type": "boolean"
    },
    "executionBatches": {
      "items": {
        "items": {
          "type": "string"
        },
        "type": "array"
      },
      "type": "array"
    },
    "inputHash": {
      "pattern": "^[a-f0-9]{64}$",
      "type": "string"
    },
    "issues": {
      "items": {
        "additionalProperties": true,
        "type": "object"
      },
      "type": "array"
    },
    "outputHash": {
      "pattern": "^[a-f0-9]{64}$",
      "type": "string"
    },
    "planId": {
      "type": "string"
    },
    "quality": {
      "additionalProperties": true,
      "type": "object"
    },
    "schemaVersion": {
      "const": "1.0.0"
    },
    "simulation": {
      "additionalProperties": true,
      "type": "object"
    },
    "specificationId": {
      "type": "string"
    },
    "topologicalOrder": {
      "items": {
        "type": "string"
      },
      "type": "array"
    }
  },
  "required": [
    "schemaVersion",
    "planId",
    "specificationId",
    "inputHash",
    "compilerVersion",
    "executable",
    "issues",
    "topologicalOrder",
    "executionBatches",
    "compiledTasks",
    "quality",
    "simulation",
    "outputHash"
  ],
  "title": "Kristin Plan Compilation Report v1",
  "type": "object"
}
''';
