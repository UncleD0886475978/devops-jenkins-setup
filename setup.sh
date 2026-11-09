#!/usr/bin/env bash
# setup.sh — devops-jenkins-setup (DevOps / Jenkins HomeLab)
# Inspection found only README.md + a labs/ directory at the root: no Jenkinsfile,
# no docker-compose.yml and no requirements.txt at root. This script therefore
# discovers the real entry point at runtime: Compose file -> Jenkinsfile/Dockerfile
# -> labs walkthrough mode.
set -e

REPO="devops-jenkins-setup"
OWNER="UncleD0886475978"
CLONE_URL="https://github.com/${OWNER}/${REPO}.git"
TARGET_DIR="$HOME/repos/${REPO}"

echo "==> Step 1/5: Locate or clone ${REPO}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d ".git" ] && git remote get-url origin 2>/dev/null | grep -qi "${REPO}"; then
  REPO_DIR="$PWD"
elif [ -d "${SCRIPT_DIR}/.git" ] && git -C "${SCRIPT_DIR}" remote get-url origin 2>/dev/null | grep -qi "${REPO}"; then
  REPO_DIR="${SCRIPT_DIR}"
elif [ -d "${TARGET_DIR}/.git" ]; then
  REPO_DIR="${TARGET_DIR}"
  git -C "${REPO_DIR}" pull --ff-only || echo "    (git pull skipped/failed — continuing with existing checkout)"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is not installed. Install it: https://git-scm.com/downloads"
    exit 1
  fi
  mkdir -p "$HOME/repos"
  git clone "${CLONE_URL}" "${TARGET_DIR}"
  REPO_DIR="${TARGET_DIR}"
fi
cd "${REPO_DIR}"
echo "    Working in: ${REPO_DIR}"

echo "==> Step 2/5: Check prerequisites (Docker for Jenkins, python3 for lab scripts)"
MISSING=0
if ! command -v docker >/dev/null 2>&1; then
  echo "MISSING: docker — install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  echo "         (Jenkins itself: https://www.jenkins.io/download/)"
  MISSING=1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "MISSING: python3 — install from https://www.python.org/downloads/ (needed by the Python lab material)"
  MISSING=1
fi
if [ "${MISSING}" -ne 0 ]; then
  echo "Install the tool(s) above, then re-run this script."
  exit 1
fi
echo "    docker:  $(docker --version)"
echo "    python3: $(python3 --version)"

echo "==> Step 3/5: Discover how this repo actually runs"
COMPOSE_FILE="$(find . -maxdepth 3 \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' \) | head -n 1)"
JENKINSFILE="$(find . -maxdepth 3 -name 'Jenkinsfile' | head -n 1)"
DOCKERFILE="$(find . -maxdepth 3 -name 'Dockerfile' | head -n 1)"
REQ_FILE="$(find . -maxdepth 3 -name 'requirements.txt' | head -n 1)"
MODE="labs"
if [ -n "${COMPOSE_FILE}" ]; then MODE="compose";
elif [ -n "${DOCKERFILE}" ]; then MODE="dockerfile";
elif [ -n "${JENKINSFILE}" ]; then MODE="jenkinsfile"; fi
echo "    Compose file: ${COMPOSE_FILE:-none found}"
echo "    Jenkinsfile:  ${JENKINSFILE:-none found}"
echo "    Dockerfile:   ${DOCKERFILE:-none found}"
echo "    requirements: ${REQ_FILE:-none found}"
echo "    Mode: ${MODE}"

echo "==> Step 4/5: Set up Python dependencies, if the repo ships any"
if [ -n "${REQ_FILE}" ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip >/dev/null
  .venv/bin/pip install -r "${REQ_FILE}"
  echo "    Installed ${REQ_FILE} into .venv — activate with: source .venv/bin/activate"
else
  echo "    No requirements.txt found — nothing to install."
fi

echo "==> Step 5/5: Start Jenkins, or walk the labs"
case "${MODE}" in
  compose)
    if ! docker info >/dev/null 2>&1; then
      echo "ERROR: Docker daemon is not running. Start Docker Desktop, then re-run."
      exit 1
    fi
    COMPOSE_DIR="$(dirname "${COMPOSE_FILE}")"
    (cd "${COMPOSE_DIR}" && docker compose up -d --build)
    echo "    Waiting for Jenkins on http://localhost:8080 ..."
    for i in $(seq 1 30); do
      if curl -fs http://localhost:8080/login >/dev/null 2>&1; then break; fi
      sleep 3
    done
    echo "    Jenkins should be at: http://localhost:8080"
    echo "    First-time admin password (if asked):  docker compose -f ${COMPOSE_FILE} exec <jenkins-service> cat /var/jenkins_home/secrets/initialAdminPassword"
    echo "    (or read it from the container logs — see Logs below)"
    ;;
  dockerfile)
    if ! docker info >/dev/null 2>&1; then
      echo "ERROR: Docker daemon is not running. Start Docker Desktop, then re-run."
      exit 1
    fi
    DF_DIR="$(dirname "${DOCKERFILE}")"
    docker build -t devops-jenkins-setup "${DF_DIR}"
    docker rm -f devops-jenkins >/dev/null 2>&1 || true
    docker run -d --name devops-jenkins -p 8080:8080 -p 50000:50000 devops-jenkins-setup
    echo "    Jenkins should be at: http://localhost:8080"
    echo "    First-time admin password:  docker exec devops-jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
    ;;
  jenkinsfile)
    echo "    This repo provides a Jenkinsfile but no way to run Jenkins itself."
    echo "    Start a stock Jenkins, then create a Pipeline job pointing at this repo:"
    echo "      docker run -d --name jenkins -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts"
    echo "    Then open http://localhost:8080 and add this repo as a 'Pipeline script from SCM' job."
    ;;
  labs)
    echo "    No Compose/Dockerfile/Jenkinsfile found — this checkout is lab material. Labs found:"
    if [ -d labs ]; then
      find labs -maxdepth 2 | sort | sed 's/^/      /'
    fi
    echo ""
    echo "    Work through the lab folders/readmes in order. To run the Jenkins these labs"
    echo "    are built around, start the official image (needs Docker running):"
    echo "      docker run -d --name jenkins -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts"
    echo "    Then open http://localhost:8080 (admin password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)"
    ;;
esac

cat <<'EOF'

✅ devops-jenkins-setup checked (entry point discovered above; Jenkins/labs ready as described).

NEXT COMMANDS
  Run/use:
    • Jenkins UI:            http://localhost:8080
    • Python lab scripts:    source .venv/bin/activate   (if a requirements.txt was installed)
  Stop:
    • Compose mode:  docker compose down        (run in the compose file's directory)
    • Container mode: docker stop devops-jenkins jenkins && docker rm devops-jenkins jenkins
  Logs:
    • Compose:   docker compose logs -f
    • Container: docker logs -f jenkins   (or devops-jenkins)
    • Jenkins home (jobs, config, admin password) lives in the jenkins_home volume / /var/jenkins_home in the container.
EOF
