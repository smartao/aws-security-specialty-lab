#!/usr/bin/env bash
# Verifica se algum lab Terraform tem recursos aplicados (state != vazio) no
# backend remoto S3, para evitar esquecer um `terraform destroy` pendente.
#
# Usa o profile AWS "conta-pes" por padrão (credenciais de longa duração, sem
# SSO), então roda sem precisar renovar sessão. Troque com --profile ou a
# variável AWS_PROFILE se quiser usar outro.
#
# Uso:
#   ./scripts/check-deployed-resources.sh                    # notifica só se houver recursos
#   ./scripts/check-deployed-resources.sh --always            # notifica mesmo se estiver tudo limpo
#   ./scripts/check-deployed-resources.sh --no-notify          # só imprime no terminal, nunca notifica
#   ./scripts/check-deployed-resources.sh --quiet               # só imprime no terminal se houver recursos; se estiver limpo, não imprime nada
#   ./scripts/check-deployed-resources.sh --profile outro-nome
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$REPO_ROOT/terraform/environments"
PROFILE="${AWS_PROFILE:-conta-pes}"
ALWAYS_NOTIFY=false
NO_NOTIFY=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --always) ALWAYS_NOTIFY=true; shift ;;
        --no-notify) NO_NOTIFY=true; shift ;;
        --quiet) QUIET=true; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
    esac
done

command -v aws >/dev/null || { echo "aws CLI não encontrado no PATH." >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq não encontrado no PATH." >&2; exit 1; }

if ! aws --profile "$PROFILE" sts get-caller-identity >/dev/null 2>&1; then
    $NO_NOTIFY || notify-send -u critical "Terraform check" "Credenciais do profile '$PROFILE' inválidas/expiradas." || true
    echo "Credenciais do profile '$PROFILE' inválidas. Rode 'aws configure --profile $PROFILE' e tente de novo." >&2
    exit 1
fi

declare -a DIRTY_LABS=()
declare -A LAB_DETAILS=()

for lab_dir in "$ENV_DIR"/*/; do
    lab="$(basename "$lab_dir")"
    versions_file="$lab_dir/versions.tf"
    [[ -f "$versions_file" ]] || continue

    bucket="$(grep -A5 'backend "s3"' "$versions_file" | grep -oP 'bucket\s*=\s*"\K[^"]+' | head -1)"
    key="$(grep -A5 'backend "s3"' "$versions_file" | grep -oP '(?<!use_lock)key\s*=\s*"\K[^"]+' | head -1)"
    region="$(grep -A5 'backend "s3"' "$versions_file" | grep -oP 'region\s*=\s*"\K[^"]+' | head -1)"

    if [[ -z "$bucket" || -z "$key" ]]; then
        echo "[$lab] backend S3 não encontrado em versions.tf, pulando." >&2
        continue
    fi

    state_file="$(mktemp)"
    if ! aws --profile "$PROFILE" s3api get-object \
        --bucket "$bucket" --key "$key" ${region:+--region "$region"} \
        "$state_file" >/dev/null 2>&1; then
        $QUIET || echo "[$lab] sem state em s3://$bucket/$key (nunca aplicado?)."
        rm -f "$state_file"
        continue
    fi

    count="$(jq '.resources | length' "$state_file")"
    if [[ "$count" -gt 0 ]]; then
        DIRTY_LABS+=("$lab")
        summary="$(jq -r '.resources[] | "\(.type).\(.name)"' "$state_file" | sort -u | head -10 | paste -sd, -)"
        LAB_DETAILS["$lab"]="$count recurso(s): $summary"
        echo "$lab: on"
    else
        $QUIET || echo "[$lab] limpo (0 recursos no state)."
    fi
    rm -f "$state_file"
done

if [[ ${#DIRTY_LABS[@]} -gt 0 ]]; then
    body="$(for lab in "${DIRTY_LABS[@]}"; do echo "• $lab: ${LAB_DETAILS[$lab]}"; done)"
    if ! $NO_NOTIFY; then
        notify-send -u critical -i dialog-warning \
            "⚠ Terraform: recursos AWS ainda de pé" \
            "$body"
    fi
    exit 2
else
    $QUIET || echo "Nenhum recurso aplicado encontrado em nenhum lab."
    if $ALWAYS_NOTIFY && ! $NO_NOTIFY; then
        notify-send -u low "Terraform check" "Tudo limpo — nenhum recurso AWS aplicado."
    fi
fi
