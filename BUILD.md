# devops-jenkins-setup — BUILD

- **Repo:** `UncleD0886475978/devops-jenkins-setup` — public, original (not a fork). Described as "DevOps-Jenkins-HomeLab (Python)".
- **Stack actually found** (via GitHub connector directory listing of the root):
  - Root contains **only** `README.md` (619 B) and a `labs/` directory.
  - **No** `Jenkinsfile`, **no** `docker-compose.yml`, **no** `Dockerfile`, **no** `requirements.txt` at root — so at root level this is lab/documentation material for a Jenkins homelab, not a runnable Jenkins definition.
- **Inspection note:** the connector returned directory listings, not file bodies, and a GitHub HTTP 429 (rate limit) stopped inspection before the contents of `labs/` could be listed. `setup.sh` therefore discovers Compose files, Dockerfiles, Jenkinsfiles and requirements files at runtime (searching the whole checkout), and falls back to a labs walkthrough if none exist.

## What setup.sh does

1. Uses the current checkout if its git remote mentions `devops-jenkins-setup` (or the script sits in the repo root); otherwise clones into `~/repos/devops-jenkins-setup` (`git pull` if already there).
2. Checks docker and python3, printing install URLs (Docker Desktop, Jenkins download page, python.org) for anything missing and exiting cleanly.
3. Discovers the real entry point at runtime: Compose file → Dockerfile → Jenkinsfile → labs-only.
4. If a `requirements.txt` exists anywhere in the checkout, installs it into a local `.venv`.
5. Starts Jenkins accordingly — `docker compose up -d --build` + wait + `http://localhost:8080` for Compose; build/run on 8080/50000 for a Dockerfile; for labs-only mode it lists the labs and prints the official `jenkins/jenkins:lts` run command instead of inventing a setup the repo doesn't define.
6. Prints next commands: Jenkins URL + initial-admin-password locations, how to stop (compose down / docker stop), and where logs live.

**Issue it prevents:** assuming a Jenkinsfile/Compose setup exists and failing mysteriously — the script proves what the repo actually ships before trying to run anything.
