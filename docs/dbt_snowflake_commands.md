# 🚀 dbt with Snowflake: Production-Grade Command Reference

This guide outlines the most frequently used and critical dbt commands for robust, production-grade data transformation using Snowflake as the data warehouse.

## ⚙️ Setup & Configuration
| Command | Purpose | Notes |
| :--- | :--- | :--- |
| `dbt init <project_name>` | Initializes a new dbt project. | Essential starting point. Follow the interactive prompts. |
| `dbt debug` | Validates your dbt connection and configuration. | Always run after environment/profile changes to ensure connectivity to Snowflake. |
| `dbt --target prod` | Specifies the production profile. | Use profiles (e.g., `prod`, `dev`) to separate environments. |

## ▶️ Core Execution
| Command | Purpose | Notes |
| :--- | :--- | :--- |
| `dbt run` | Compiles and executes models against Snowflake. | This is the main transformation step. Runs only models defined in your project. |
| `dbt seed` | Loads static data (e.g., CSV files) into dbt staging tables. | Used for reference data. Ensure your `seeds` directory is configured. |
| `dbt compile` | Compiles dbt SQL models into native Snowflake SQL. | Useful for local testing and validation before running against the live warehouse. |

## ✅ Quality & Validation
| Command | Purpose | Notes |
| :--- | :--- | :--- |
| `dbt test` | Runs defined data quality tests (e.g., `unique`, `not_null`) in Snowflake. | **CRITICAL for production.** Never run `dbt run` without first running `dbt test`. |
| `dbt docs generate` | Generates the dbt documentation site (JSON artifacts). | Required before serving documentation. Creates the `target/` directory. |
| `dbt docs serve` | Serves the generated documentation site locally. | Allows review of models, columns, and tests in a browsable format. |

## 🛠️ Advanced Workflow
| Command | Purpose | Notes |
| :--- | :--- | :--- |
| `dbt build --target prod` | Combines `dbt run`, `dbt test`, and `dbt docs generate`. | The preferred command for full, production-ready execution of a model run. |
| `dbt snapshot` | Creates historical snapshots of tables. | Use for slowly changing dimensions (SCD Type 2) in Snowflake. |

> **💡 Production Tip:** Always define a robust CI/CD pipeline using `dbt build --target prod` on every push to your main branch. This ensures data quality and documentation are consistently generated before deployment to Snowflake.