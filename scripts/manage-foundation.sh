#!/usr/bin/env bash
# Deploy ou destroi a fundação (lab01 + lab02) de uma vez só, na ordem certa.
#
# Lab02 lê a VPC do Lab01 via SSM Parameter Store (não terraform_remote_state
# — ver terraform/environments/lab02/data.tf), então a ordem importa:
#   up:   lab01 -> lab02   (lab02 precisa do parâmetro /lab01/vpc_id já publicado)
#   down: lab02 -> lab01   (senão o destroy do lab02 falha lendo um SSM que já sumiu)
#
# Cada lab usa terraform apply/destroy interativo (confirmação "yes" do
# próprio Terraform) a menos que --auto-approve seja passado.
#
# Uso:
#   ./scripts/manage-foundation.sh up
#   ./scripts/manage-foundation.sh up --auto-approve
#   ./scripts/manage-foundation.sh down
#   ./scripts/manage-foundation.sh down --auto-approve
#   ./scripts/manage-foundation.sh up --profile outro-profile-sso
#   ./scripts/manage-foundation.sh up --region us-west-2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$REPO_ROOT/terraform/environments"

ACTION="${1:-}"
shift || true

case "$ACTION" in
    up|down) ;;
    *)
        echo "Uso: $0 {up|down} [--auto-approve] [--profile nome] [--region regiao]" >&2
        exit 1
        ;;
esac

AUTO_APPROVE=false
declare -a TF_VARS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-approve) AUTO_APPROVE=true; shift ;;
        --profile) TF_VARS+=("-var=aws_profile=$2"); shift 2 ;;
        --region)  TF_VARS+=("-var=aws_region=$2");  shift 2 ;;
        *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
    esac
done

command -v terraform >/dev/null || { echo "terraform não encontrado no PATH." >&2; exit 1; }

if [[ "$ACTION" == "up" ]]; then
    LABS=(lab01 lab02)
    TF_ACTION=apply
else
    LABS=(lab02 lab01)
    TF_ACTION=destroy
fi

for lab in "${LABS[@]}"; do
    dir="$ENV_DIR/$lab"
    [[ -d "$dir" ]] || { echo "[$lab] diretório não encontrado em $dir, abortando." >&2; exit 1; }

    echo
    echo "== [$lab] terraform init =="
    terraform -chdir="$dir" init -input=false

    echo "== [$lab] terraform $TF_ACTION =="
    if $AUTO_APPROVE; then
        terraform -chdir="$dir" "$TF_ACTION" -auto-approve "${TF_VARS[@]}"
    else
        terraform -chdir="$dir" "$TF_ACTION" "${TF_VARS[@]}"
    fi
done

echo
if [[ "$ACTION" == "up" ]]; then
    echo "Fundação (lab01 + lab02) aplicada."
else
    echo "Fundação (lab01 + lab02) destruída. Rode ./scripts/check-deployed-resources.sh para confirmar que ficou tudo limpo."
fi
