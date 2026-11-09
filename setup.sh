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
RUN_ONELINE="curl -fsSL https://raw.githubusercontent.com/${OWNER}/${REPO}/main/setup.sh | bash"

echo "==> Step 1/6: Platform check + base bootstrap (git, curl)"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: this script needs root or sudo to install packages."
    exit 1
  fi
fi
APT=0
if [ "$(uname -s)" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then APT=1; fi
INSTALLED=""
APT_UPDATED=""
note_installed() { INSTALLED="${INSTALLED} $1"; }
apt_update_once() {
  if [ -z "${APT_UPDATED}" ]; then $SUDO apt-get update -y; APT_UPDATED=1; fi
}
apt_install() {
  apt_update_once
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "$@"
}
if [ "${APT}" -eq 1 ]; then
  BASE_PKGS=""
  command -v git >/dev/null 2>&1 || BASE_PKGS="${BASE_PKGS} git"
  command -v curl >/dev/null 2>&1 || BASE_PKGS="${BASE_PKGS} curl"
  [ -f /etc/ssl/certs/ca-certificates.crt ] || BASE_PKGS="${BASE_PKGS} ca-certificates"
  command -v gpg >/dev/null 2>&1 || BASE_PKGS="${BASE_PKGS} gnupg"
  if [ -n "${BASE_PKGS}" ]; then
    echo "    Installing base tools:${BASE_PKGS}"
    # shellcheck disable=SC2086
    apt_install ${BASE_PKGS}
    note_installed "${BASE_PKGS}"
  else
    echo "    Base tools already present (git, curl, ca-certificates, gnupg)."
  fi
else
  echo "    Non-apt platform detected — bootstrap will only CHECK tools and print install guidance."
fi

echo "==> Step 2/6: Locate or clone ${REPO}"
if [ -f "$0" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
  SCRIPT_DIR="$PWD"
fi
if [ -d ".git" ] && command -v git >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -qi "${REPO}"; then
  REPO_DIR="$PWD"
elif [ -d "${SCRIPT_DIR}/.git" ] && command -v git >/dev/null 2>&1 && git -C "${SCRIPT_DIR}" remote get-url origin 2>/dev/null | grep -qi "${REPO}"; then
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

echo "==> Step 3/6: Bootstrap prerequisites (Docker for Jenkins, python3 for lab scripts)"
DOCKER="docker"
install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "    docker: already present ($(docker --version))"
  elif [ "${APT}" -eq 1 ]; then
    echo "    Installing Docker Engine via the official get.docker.com script..."
    curl -fsSL https://get.docker.com | $SUDO sh
    note_installed "docker"
  else
    return 1
  fi
  if ! docker info >/dev/null 2>&1 && ! $SUDO docker info >/dev/null 2>&1; then
    echo "    Starting the Docker daemon..."
    $SUDO systemctl enable --now docker 2>/dev/null || $SUDO service docker start 2>/dev/null || true
    for _i in $(seq 1 15); do
      if docker info >/dev/null 2>&1 || $SUDO docker info >/dev/null 2>&1; then break; fi
      sleep 2
    done
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER="docker"
  elif $SUDO docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
    if [ "$(id -u)" -ne 0 ]; then
      $SUDO usermod -aG docker "$USER" 2>/dev/null || true
      echo "    NOTE: you were added to the 'docker' group (applies at next login); this run uses 'sudo docker'."
    fi
  else
    echo "ERROR: Docker is installed but the daemon could not be started."
    echo "       On a VM:  sudo systemctl start docker   |   In a container/WSL without systemd, Docker cannot run here."
    exit 1
  fi
  echo "    docker daemon OK (using: ${DOCKER})"
}
install_python() {
  if command -v python3 >/dev/null 2>&1 && python3 -c "import venv" >/dev/null 2>&1; then echo "    python3 + venv: already present ($(python3 --version))"; return 0; fi
  [ "${APT}" -eq 1 ] || return 1
  echo "    Installing python3, venv and pip..."
  apt_install python3 python3-venv python3-pip
  note_installed "python3"
}
MISSING_LIST=""
install_docker || MISSING_LIST="${MISSING_LIST} docker(https://www.docker.com/products/docker-desktop/ ; Jenkins: https://www.jenkins.io/download/)"
install_python || MISSING_LIST="${MISSING_LIST} python3(https://www.python.org/downloads/)"
if [ -n "${MISSING_LIST}" ]; then
  echo "ERROR: could not auto-install on this platform. Missing:${MISSING_LIST}"
  echo "Install the tool(s) manually, then re-run this script."
  exit 1
fi
# shellcheck disable=SC2086
${DOCKER} compose version >/dev/null 2>&1 || { if [ "${APT}" -eq 1 ]; then apt_install docker-compose-plugin; fi; }
echo "    docker:  $(docker --version)"
echo "    python3: $(python3 --version)"

echo "==> Step 4/6: Discover how this repo actually runs"
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

echo "==> Step 5/6: Set up Python dependencies, if the repo ships any"
if [ -n "${REQ_FILE}" ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip >/dev/null
  .venv/bin/pip install -r "${REQ_FILE}"
  echo "    Installed ${REQ_FILE} into .venv — activate with: source .venv/bin/activate"
else
  echo "    No requirements.txt found — nothing to install."
fi

echo "==> Step 6/6: Start Jenkins, or walk the labs"
case "${MODE}" in
  compose)
    # shellcheck disable=SC2086
    if ! ${DOCKER} info >/dev/null 2>&1; then
      echo "ERROR: Docker daemon is not running. Start Docker Desktop, then re-run."
      exit 1
    fi
    COMPOSE_DIR="$(dirname "${COMPOSE_FILE}")"
    # shellcheck disable=SC2086
    (cd "${COMPOSE_DIR}" && ${DOCKER} compose up -d --build)
    echo "    Waiting for Jenkins on http://localhost:8080 ..."
    for i in $(seq 1 30); do
      if curl -fs http://localhost:8080/login >/dev/null 2>&1; then break; fi
      sleep 3
    done
    echo "    Jenkins should be at: http://localhost:8080"
    echo "    First-time admin password (if asked):  ${DOCKER} compose -f ${COMPOSE_FILE} exec <jenkins-service> cat /var/jenkins_home/secrets/initialAdminPassword"
    echo "    (or read it from the container logs — see Logs below)"
    ;;
  dockerfile)
    # shellcheck disable=SC2086
    if ! ${DOCKER} info >/dev/null 2>&1; then
      echo "ERROR: Docker daemon is not running. Start Docker Desktop, then re-run."
      exit 1
    fi
    DF_DIR="$(dirname "${DOCKERFILE}")"
    # shellcheck disable=SC2086
    ${DOCKER} build -t devops-jenkins-setup "${DF_DIR}"
    # shellcheck disable=SC2086
    ${DOCKER} rm -f devops-jenkins >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    ${DOCKER} run -d --name devops-jenkins -p 8080:8080 -p 50000:50000 devops-jenkins-setup
    echo "    Jenkins should be at: http://localhost:8080"
    echo "    First-time admin password:  ${DOCKER} exec devops-jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
    ;;
  jenkinsfile)
    echo "    This repo provides a Jenkinsfile but no way to run Jenkins itself."
    echo "    Start a stock Jenkins, then create a Pipeline job pointing at this repo:"
    echo "      ${DOCKER} run -d --name jenkins -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts"
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
    echo "      ${DOCKER} run -d --name jenkins -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts"
    echo "    Then open http://localhost:8080 (admin password: ${DOCKER} exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)"
    ;;
esac

cat <<EOF

=================== BOOTSTRAP SUMMARY ===================
Installed during this run:${INSTALLED:- (nothing — all tools were already present)}
Working copy: ${REPO_DIR}
Next time, set up from scratch on any fresh Ubuntu VM with one line:
  ${RUN_ONELINE}
=========================================================
EOF

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
