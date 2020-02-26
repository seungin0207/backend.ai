#! /bin/bash

# Set "echo -e" as default
shopt -s xpg_echo

RED="\033[0;91m"
GREEN="\033[0;92m"
YELLOW="\033[0;93m"
BLUE="\033[0;94m"
CYAN="\033[0;96m"
WHITE="\033[0;97m"
LRED="\033[1;31m"
LGREEN="\033[1;32m"
LYELLOW="\033[1;33m"
LBLUE="\033[1;34m"
LCYAN="\033[1;36m"
LWHITE="\033[1;37m"
LG="\033[0;37m"
NC="\033[0m"
REWRITELN="\033[A\r\033[K"

readlinkf() {
  $bpython -c "import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))" "${1}"
}

trim() {
  echo "$1" | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g'
}

usage() {
  echo "${GREEN}Backend.AI Development Setup${NC}: ${CYAN}Auto-installer Tool${NC}"
  echo ""
  echo "${LWHITE}USAGE${NC}"
  echo "  $0 ${LWHITE}[OPTIONS]${NC}"
  echo ""
  echo "${LWHITE}OPTIONS${NC}"
  echo "  ${LWHITE}-h, --help${NC}           Show this help message and exit"
  echo ""
  echo "  ${LWHITE}--python-version VERSION${NC}"
  echo "                       Set the Python version to install via pyenv"
  echo "                       (default: 3.6.9)"
  echo ""
  echo "  ${LWHITE}--install-path PATH${NC}  Set the target directory"
  echo "                       (default: ./backend.ai-dev)"
  echo ""
  echo "  ${LWHITE}--server-branch NAME${NC}"
  echo "                       The branch of git clones for server components"
  echo "                       (default: master)"
  echo ""
  echo "  ${LWHITE}--client-branch NAME${NC}"
  echo "                       The branch of git clones for client components"
  echo "                       (default: master)"
  echo ""
  echo "  ${LWHITE}--enable-cuda${NC}        Install CUDA accelerator plugin and pull a"
  echo "                       TenosrFlow CUDA kernel for testing/demo."
  echo "                       (default: false)"
  echo ""
  echo "  ${LWHITE}--cuda-branch NAME${NC}   The branch of git clone for the CUDA accelerator "
  echo "                       plugin; only valid if ${LWHITE}--enable-cuda${NC} is specified."
  echo "                       (default: master)"
}

show_error() {
  echo " "
  echo "${RED}[ERROR]${NC} ${LRED}$1${NC}"
}

show_warning() {
  echo " "
  echo "${YELLOW}[ERROR]${NC} ${LYELLOW}$1${NC}"
}

show_info() {
  echo " "
  echo "${BLUE}[INFO]${NC} ${GREEN}$1${NC}"
}

show_note() {
  echo " "
  echo "${BLUE}[NOTE]${NC} $1"
}

show_important_note() {
  echo " "
  echo "${LRED}[NOTE]${NC} $1"
}

has_python() {
  "$1" -c '' >/dev/null 2>&1
  if [ "$?" -eq 127 ]; then
    echo 0
  else
    echo 1
  fi
}

if [[ "$OSTYPE" == "linux-gnu" ]]; then
  if [ $(id -u) = "0" ]; then
    docker_sudo=''
  else
    docker_sudo='sudo'
  fi
else
  docker_sudo=''
fi
if [ $(id -u) = "0" ]; then
  sudo=''
else
  sudo='sudo'
fi

# Detect distribution
KNOWN_DISTRO="(Debian|Ubuntu|RedHat|CentOS|openSUSE|Amazon|Arista|SUSE)"
DISTRO=$(lsb_release -d 2>/dev/null | grep -Eo $KNOWN_DISTRO  || grep -Eo $KNOWN_DISTRO /etc/issue 2>/dev/null || uname -s)

if [ $DISTRO = "Darwin" ]; then
  DISTRO="Darwin"
elif [ -f /etc/debian_version -o "$DISTRO" == "Debian" -o "$DISTRO" == "Ubuntu" ]; then
  DISTRO="Debian"
elif [ -f /etc/redhat-release -o "$DISTRO" == "RedHat" -o "$DISTRO" == "CentOS" -o "$DISTRO" == "Amazon" ]; then
  DISTRO="RedHat"
elif [ -f /etc/system-release -o "$DISTRO" == "Amazon" ]; then
  DISTRO="RedHat"
else
  show_error "Sorry, your host OS distribution is not supported by this script."
  show_info "Please send us a pull request or file an issue to support your environment!"
  exit 1
fi
if [ $(has_python "python") -eq 1 ]; then
  bpython=$(which "python")
elif [ $(has_python "python3") -eq 1 ]; then
  bpython=$(which "python3")
elif [ $(has_python "python2") -eq 1 ]; then
  bpython=$(which "python2")
else
  # Ensure "readlinkf" is working...
  show_error "python (for bootstrapping) is not available!"
  show_info "This script assumes Python 2.7+/3+ is already available on your system."
  exit 1
fi

ROOT_PATH=$(pwd)
PYTHON_VERSION="3.6.10"
SERVER_BRANCH="19.09"
CLIENT_BRANCH="19.09"
INSTALL_PATH="./backend.ai-dev"
DOWNLOAD_BIG_IMAGES=0
ENABLE_CUDA=0
CUDA_BRANCH="master"

while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)           usage; exit 1 ;;
    --python-version)      PYTHON_VERSION=$2; shift ;;
    --python-version=*)    PYTHON_VERSION="${1#*=}" ;;
    --install-path)        INSTALL_PATH=$2; shift ;;
    --install-path=*)      INSTALL_PATH="${1#*=}" ;;
    --server-branch)       SERVER_BRANCH=$2; shift ;;
    --server-branch=*)     SERVER_BRANCH="${1#*=}" ;;
    --client-branch)       CLIENT_BRANCH=$2; shift ;;
    --client-branch=*)     CLIENT_BRANCH="${1#*=}" ;;
    --enable-cuda)         ENABLE_CUDA=1 ;;
    --download-big-images) DOWNLOAD_BIG_IMAGES=1 ;;
    --cuda-branch)         CUDA_BRANCH=$2; shift ;;
    --cuda-branch=*)       CUDA_BRANCH="${1#*=}" ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage."
      exit 1
  esac
  shift
done
INSTALL_PATH=$(readlinkf "$INSTALL_PATH")

install_brew() {
    case $DISTRO in
	Darwin)
	    if ! type "brew" > /dev/null 2>&1; then
	        show_info "try to support auto-install on macOS using Homebrew."
		/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
	    fi
    esac
}
install_script_deps() {
  case $DISTRO in
  Debian)
    $sudo apt-get update
    $sudo apt-get install -y git
    ;;
  RedHat)
    $sudo yum clean expire-cache  # next yum invocation will update package metadata cache
    $sudo yum install -y git
    ;;
  Darwin)
    if ! type "brew" >/dev/null 2>&1; then
      show_error "brew is not available!"
      show_info "Sorry, we only support auto-install on macOS using Homebrew. Please install it and try again."
      install_brew
    fi
    brew update
    # Having Homebrew means that the user already has git.
    ;;
  esac
}

install_pybuild_deps() {
  case $DISTRO in
  Debian)
    $sudo apt-get install -y libssl-dev libreadline-dev libgdbm-dev zlib1g-dev libbz2-dev libsqlite3-dev libffi-dev liblzma-dev
    ;;
  RedHat)
    $sudo yum install -y openssl-devel readline-devel gdbm-devel zlib-devel bzip2-devel libsqlite-devel libffi-devel lzma-devel
    ;;
  Darwin)
    brew bundle --file=- <<"EOS"
brew "openssl"
brew "sqlite3"
brew "readline"
brew "zlib"
brew "xz"
brew "gdbm"
brew "tcl-tk"
brew "snappy"
EOS
    ;;
  esac
}

install_git_lfs() {
  case $DISTRO in
  Debian)
    $sudo apt-get install -y git-lfs
    ;;
  RedHat)
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | $sudo bash
    $sudo yum install -y git-lfs
    ;;
  Darwin)
    brew bundle --file=- <<"EOS"
brew "git-lfs"
EOS
    ;;
  esac
  git lfs install
}

install_system_pkg() {
  # accepts three args: Debian-style name, RedHat-style name, and Homebrew-style name
  case $DISTRO in
  Debian)
    $sudo apt-get install -y $1
    ;;
  RedHat)
    $sudo yum install -y $2
    ;;
  Darwin)
    brew bundle --file=- <<EOS
brew "$3"
EOS
  esac
}

install_docker() {
  show_info "Install docker"
  case $DISTRO in
  Debian)
    sudo curl -fsSL https://get.docker.io | bash
    sudo usermod -aG docker $(whoami)
    ;;
  RedHat)
    sudo curl -fsSL https://get.docker.io | bash
    sudo usermod -aG docker $(whoami)
    ;;
  Darwin)
    show_info "Please install the latest version of docker and try again."
    show_info "It should have been installed with Docker Desktop for Mac or Docker Toolbox."
    show_info " - Instructions: https://docs.docker.com/install/"
    show_info"  - Download: https://download.docker.com/mac/stable/Docker.dmg"
    exit 1
    ;;
  esac
}

install_docker_compose() {
  show_info "Install docker-compose"
  case $DISTRO in
  Debian)
    sudo curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    ;;
  RedHat)
    sudo curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    ;;
  Darwin)
    show_info "Please install the latest version of docker-compose and try again."
    show_info "It should have been installed with Docker Desktop for Mac or Docker Toolbox."
    show_info " - Instructions: https://docs.docker.com/compose/install/"
    show_info"  - Download: https://download.docker.com/mac/stable/Docker.dmg"
    exit 1
    ;;
  esac
}

install_python() {
  if [ -z "$(pyenv versions | grep -E "^\\*?[[:space:]]+${PYTHON_VERSION//./\\.}([[:blank:]]+.*)?$")" ]; then
    if [ "$DISTRO" = "Darwin" ]; then
      export PYTHON_CONFIGURE_OPTS="--enable-framework --with-tcl-tk"
      local _prefix_openssl="$(brew --prefix openssl)"
      local _prefix_sqlite3="$(brew --prefix sqlite3)"
      local _prefix_readline="$(brew --prefix readline)"
      local _prefix_zlib="$(brew --prefix zlib)"
      local _prefix_gdbm="$(brew --prefix gdbm)"
      local _prefix_tcltk="$(brew --prefix tcl-tk)"
      local _prefix_xz="$(brew --prefix xz)"
      export CFLAGS="-I${_prefix_openssl}/include -I${_prefix_sqlite3}/include -I${_prefix_readline}/include -I${_prefix_zlib}/include -I${_prefix_gdbm}/include -I${_prefix_tcltk}/include -I${_prefix_xz}/include"
      export LDFLAGS="-L${_prefix_openssl}/lib -L${_prefix_sqlite3}/lib -L${_prefix_readline}/lib -L${_prefix_zlib}/lib -L${_prefix_gdbm}/lib -L${_prefix_tcltk}/lib -L${_prefix_xz}/lib"
    fi
    pyenv install --skip-existing "${PYTHON_VERSION}"
    if [ "$DISTRO" = "Darwin" ]; then
      unset PYTHON_CONFIGURE_OPTS
      unset CFLAGS
      unset LDFLAGS
    fi
    if [ $? -ne 0 ]; then
      show_error "Installing the Python version ${PYTHON_VERSION} via pyenv has failed."
      show_note "${PYTHON_VERSION} is not supported by your current installation of pyenv."
      show_note "Please update pyenv or lower PYTHON_VERSION in install-dev.sh script."
      exit 1
    fi
  else
    echo "${PYTHON_VERSION} is already installed."
  fi
}

check_python() {
  pyenv shell "${PYTHON_VERSION}"
  local _pyprefix=$(python -c 'import sys; print(sys.prefix, end="")')
  python -c 'import ssl' > /dev/null 2>&1 /dev/null
  if [ $? -ne 0 ]; then
    show_error "Your Python (prefix: ${_pyprefix}) is missing SSL support. Please reinstall or rebuild it."
    exit 1
  else
    echo "SSL support: ok"
  fi
  python -c 'import lzma' > /dev/null 2>&1 /dev/null
  if [ $? -ne 0 ]; then
    show_error "Your Python (prefix: ${_pyprefix}) is missing LZMA (XZ) support. Please reinstall or rebuild it."
    exit 1
  else
    echo "LZMA support: ok"
  fi
  pyenv shell --unset
}

# BEGIN!

echo " "
echo "${LGREEN}Backend.AI one-line installer for developers${NC}"

# NOTE: docker-compose enforces lower-cased project names
ENV_ID=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
show_note "Your environment ID is ${YELLOW}${ENV_ID}${NC}."

# Check prerequisites
show_info "Checking prerequisites and script dependencies..."
install_script_deps
if ! type "docker" >/dev/null 2>&1; then
  show_warning "docker is not available; trying to install it automatically..."
  install_docker
fi
if ! type "docker-compose" >/dev/null 2>&1; then
  show_warning "docker-compose is not available; trying to install it automatically..."
  install_docker_compose
fi
if [ "$DISTRO" = "Darwin" ]; then
  echo "validating Docker Desktop mount permissions..."
  docker pull alpine:3.8 > /dev/null
  docker run --rm -v "$HOME/.pyenv:/root/vol" alpine:3.8 ls /root/vol > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    # backend.ai-krunner-DISTRO pkgs are installed in pyenv's virtualenv,
    # so ~/.pyenv must be mountable.
    show_error "You must allow mount of '$HOME/.pyenv' in the File Sharing preference of the Docker Desktop app."
    exit 1
  fi
  docker run --rm -v "$INSTALL_PATH:/root/vol" alpine:3.8 ls /root/vol > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    show_error "You must allow mount of '$INSTALL_PATH' in the File Sharing preference of the Docker Desktop app."
    exit 1
  fi
  echo "${REWRITELN}validating Docker Desktop mount permissions: ok"
fi

# Install pyenv
read -r -d '' pyenv_init_script <<"EOS"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOS
if ! type "pyenv" >/dev/null 2>&1; then
  # TODO: ask if install pyenv
  show_info "Installing pyenv..."
  set -e
  curl https://pyenv.run | sh
  for PROFILE_FILE in "zshrc" "bashrc" "profile" "bash_profile"
  do
    if [ -e "${HOME}/.${PROFILE_FILE}" ]
    then
      echo "$pyenv_init_script" >> "${HOME}/.${PROFILE_FILE}"
    fi
  done
  set +e
  eval "$pyenv_init_script"
  pyenv
else
  eval "$pyenv_init_script"
fi

# Install Python and pyenv virtualenvs
show_info "Checking and installing Python dependencies..."
install_pybuild_deps

show_info "Checking and installing git lfs support..."
install_git_lfs

show_info "Installing Python..."
install_python

show_info "Checking Python features..."
check_python

show_info "Creating virtualenv on pyenv..."
pyenv virtualenv "${PYTHON_VERSION}" "venv-${ENV_ID}-manager"
pyenv virtualenv "${PYTHON_VERSION}" "venv-${ENV_ID}-agent"
pyenv virtualenv "${PYTHON_VERSION}" "venv-${ENV_ID}-common"
pyenv virtualenv "${PYTHON_VERSION}" "venv-${ENV_ID}-client"

# Make directories
show_info "Creating the install directory..."
mkdir -p "${INSTALL_PATH}"
cd "${INSTALL_PATH}"

# Install postgresql, etcd packages via docker
show_info "Launching the docker-compose \"halfstack\"..."
git clone --branch "${SERVER_BRANCH}" https://github.com/lablup/backend.ai
cd backend.ai
$docker_sudo docker-compose -f docker-compose.halfstack.yml -p "${ENV_ID}" up -d
$docker_sudo docker ps | grep "${ENV_ID}"   # You should see three containers here.

# Clone source codes
show_info "Cloning backend.ai source codes..."
cd "${INSTALL_PATH}"
git clone --branch "${SERVER_BRANCH}" https://github.com/lablup/backend.ai-manager manager
git clone --branch "${SERVER_BRANCH}" https://github.com/lablup/backend.ai-agent agent
git clone --branch "${SERVER_BRANCH}" https://github.com/lablup/backend.ai-common common
if [ $ENABLE_CUDA -eq 1 ]; then
  git clone --branch "${CUDA_BRANCH}" https://github.com/lablup/backend.ai-accelerator-cuda accel-cuda
fi

check_snappy() {
  pip download python-snappy
  local pkgfile=$(ls | grep snappy)
  if [[ $pkgfile =~ .*\.tar.gz ]]; then
    # source build is required!
    install_system_pkg "libsnappy-dev" "libsnappy-devel" "snappy"
  fi
  rm -f $pkgfile
}

show_info "Install packages on virtual environments..."
cd "${INSTALL_PATH}/manager"
pyenv local "venv-${ENV_ID}-manager"
pip install -U -q pip setuptools
check_snappy
pip install -U -e ../common -r requirements/dev.txt

cd "${INSTALL_PATH}/agent"
pyenv local "venv-${ENV_ID}-agent"
pip install -U -q pip setuptools
pip install -U -e ../common -r requirements/dev.txt
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  $sudo setcap cap_sys_ptrace,cap_sys_admin,cap_dac_override+eip $(readlinkf $(pyenv which python))
fi
if [ $ENABLE_CUDA -eq 1 ]; then
  cd "${INSTALL_PATH}/accel-cuda"
  pyenv local "venv-${ENV_ID}-agent"  # share the agent's venv
  pip install -U -e .
fi

cd "${INSTALL_PATH}/common"
pyenv local "venv-${ENV_ID}-common"
pip install -U -q pip setuptools
pip install -U -r requirements/dev.txt

# Copy default configurations
show_info "Copy default configuration files to manager / agent root..."
cd "${INSTALL_PATH}/manager"
pyenv local "venv-${ENV_ID}-manager"
cp config/halfstack.toml ./manager.toml
cp config/halfstack.alembic.ini ./alembic.ini
python -m ai.backend.manager.cli etcd put config/redis/addr 127.0.0.1:8110

cd "${INSTALL_PATH}/agent"
pyenv local "venv-${ENV_ID}-agent"
cp config/halfstack.toml ./agent.toml

# Docker registry setup
show_info "Configuring the Lablup's official Docker registry..."
cd "${INSTALL_PATH}/manager"
./scripts/run-with-halfstack.sh python -m ai.backend.manager.cli etcd put config/docker/registry/index.docker.io "https://registry-1.docker.io"
./scripts/run-with-halfstack.sh python -m ai.backend.manager.cli etcd put config/docker/registry/index.docker.io/username "lablup"
./scripts/run-with-halfstack.sh python -m ai.backend.manager.cli etcd rescan-images index.docker.io
./scripts/run-with-halfstack.sh python -m ai.backend.manager.cli etcd alias python python:3.6-ubuntu18.04

# Virtual folder setup
show_info "Setting up virtual folder..."
mkdir -p "${INSTALL_PATH}/vfolder/local"
cd "${INSTALL_PATH}/manager"
./scripts/run-with-halfstack.sh python -m ai.backend.manager.cli etcd put volumes/_mount "${INSTALL_PATH}/vfolder"
./scripts/run-with-halfstack.sh python -m ai.backend.manager.cli etcd put volumes/_default_host "local"
cd "${INSTALL_PATH}/agent"
mkdir -p scratches

# DB schema
show_info "Setting up databases..."
cd "${INSTALL_PATH}/manager"
cp alembic.ini.sample alembic.ini
python -m ai.backend.manager.cli schema oneshot
python -m ai.backend.manager.cli fixture populate sample-configs/example-keypairs.json
python -m ai.backend.manager.cli fixture populate sample-configs/example-resource-presets.json

show_info "Installing Python client SDK/CLI source..."
cd "${INSTALL_PATH}"
# Install python client package
git clone --branch "${CLIENT_BRANCH}" https://github.com/lablup/backend.ai-client-py client-py
cd "${INSTALL_PATH}/client-py"
pyenv local "venv-${ENV_ID}-client"
pip install -U -q pip setuptools
pip install -U -r requirements/dev.txt

show_info "Pre-pulling frequently used kernel images..."
echo "NOTE: Other images will be downloaded from the docker registry when requested.\n"
$docker_sudo docker pull lablup/python:2.7-ubuntu18.04
$docker_sudo docker pull lablup/python:3.6-ubuntu18.04
if [ $DOWNLOAD_BIG_IMAGES -eq 1 ]; then
  $docker_sudo docker pull lablup/python-tensorflow:1.14-py36
  $docker_sudo docker pull lablup/python-pytorch:1.1-py36
  if [ $ENABLE_CUDA -eq 1 ]; then
      $docker_sudo docker pull lablup/python-tensorflow:1.14-py36-cuda9
      $docker_sudo docker pull lablup/python-pytorch:1.1-py36-cuda10
      $docker_sudo docker pull lablup/ngc-digits:19.05-tensorflow
      $docker_sudo docker pull lablup/ngc-pytorch:19.05-py3
      $docker_sudo docker pull lablup/ngc-tensorflow:19.05-py3
  fi
fi

DELETE_OPTS=''
if [ ! "$INSTALL_PATH" = $(readlinkf "./backend.ai-dev") ]; then
  DELETE_OPTS+=" --install-path=${INSTALL_PATH}"
fi
DELETE_OPTS=$(trim "$DELETE_OPTS")

cd "${INSTALL_PATH}"
show_info "Installation finished."
show_note "Default API keypair configuration for test / develop:"
echo "> ${WHITE}export BACKEND_ENDPOINT=http://127.0.0.1:8081/${NC}"
echo "> ${WHITE}export BACKEND_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE${NC}"
echo "> ${WHITE}export BACKEND_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY${NC}"
echo " "
echo "Please add these environment variables to your shell configuration files."
show_important_note "You should change your default admin API keypairs for production environment!"
show_note "How to run Backend.AI manager:"
echo "> ${WHITE}cd ${INSTALL_PATH}/manager${NC}"
echo "> ${WHITE}python -m ai.backend.gateway.server --debug${NC}"
show_note "How to run Backend.AI agent:"
echo "> ${WHITE}cd ${INSTALL_PATH}/agent${NC}"
echo "> ${WHITE}python -m ai.backend.agent.server --debug${NC}"
show_note "How to run your first code:"
echo "> ${WHITE}cd ${INSTALL_PATH}/client-py${NC}"
echo "> ${WHITE}backend.ai --help${NC}"
echo "> ${WHITE}backend.ai run python -c \"print('Hello World\\!')\"${NC}"
echo " "
echo "${GREEN}Development environment is now ready.${NC}"
show_note "Reminder: Your environment ID is ${YELLOW}${ENV_ID}${NC}."
echo "  * When using docker-compose, do:"
echo "    > ${WHITE}cd ${INSTALL_PATH}/backend.ai${NC}"
if [ ! -z "$docker_sudo" ]; then
  echo "    > ${WHITE}${docker_sudo} docker-compose -p ${ENV_ID} -f docker-compose.halfstack.yml up -d ...${NC}"
else
  echo "    > ${WHITE}docker-compose -p ${ENV_ID} -f docker-compose.halfstack.yml up -d ...${NC}"
fi
echo "  * To delete this development environment, run:"
echo "    > ${WHITE}$(dirname $0)/delete-dev.sh --env ${ENV_ID} ${DELETE_OPTS}${NC}"
echo " "
