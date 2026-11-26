# ~/.config/pharmacolibrary

Template for the per-user configuration and keys. They live outside every repository:

| System | Folder |
|---|---|
| Linux, VM, WSL | `~/.config/pharmacolibrary` (mode 700, files 600) |
| Windows | `%USERPROFILE%\.config\pharmacolibrary`; `windows\setup.cmd` copies it into WSL |

Copy the files you need, drop the `.example` suffix and replace the content. Each key file holds only the key, on one line. An environment variable with the file's name in upper case (e.g. `EINFRACZ_API_KEY`) takes precedence; for the Neo4j password it is `PK_GRAPH_PASSWORD`.

| File | Content | Used by |
|---|---|---|
| `einfracz_api_key` | e-INFRA CZ LLM API key (llm.ai.e-infra.cz) | default LLM of the pipeline and the dashboard |
| `openai_api_key` | OpenAI or OpenAI-compatible API key | `pk/agent.py`, dashboard |
| `ollama_api_key` | Ollama Cloud API key | `pk/agent.py`, dashboard |
| `ncbi_api_key` | NCBI E-utilities API key | `literature/fetch_pubmed.py` |
| `s2_api_key` | Semantic Scholar API key | `literature/download.py` |
| `neo4j_password` | Neo4j password, hex without `/` (`openssl rand -hex 20`) | `scripts/run_neo4j.sh`, `export/graph_sync.py` |
| `zenodo_access_token` | Zenodo personal token of the record owner | `export/zenodo_pack.py`; `bootstrap-dbs.sh` for unpublished drafts |
| `zenodo-links.txt` | Zenodo share links of unpublished drafts, one per line | `bootstrap-dbs.sh`, `windows\setup.ps1` |
| `dashboard/resources.yaml` | dashboard LLM resources; start from `pharmacolibrary-pipeline/pharmacolib/dashboard/resources.example.yaml` | dashboard |

`windows\setup.ps1` copies only files that WSL does not have yet. It skips `*.example`, `README*` and empty files, and it reports a file that differs instead of overwriting it.
