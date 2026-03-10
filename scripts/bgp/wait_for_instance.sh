#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
tag_key=$(jq -r '.tag_key'    <<<"$INPUT")
tag_value=$(jq -r '.tag_value'<<<"$INPUT")
region=$(jq -r '.region'      <<<"$INPUT")
timeout_s=$(jq -r '.timeout_s'<<<"$INPUT")
sleep_s=$(jq -r '.sleep_s'    <<<"$INPUT")

deadline=$(( $(date +%s) + timeout_s ))

while true; do
  # Fetch both PrivateIpAddress and InstanceId
  INSTANCE_DATA=$(aws ec2 describe-instances \
      --region "$region" \
      --filters "Name=tag:${tag_key},Values=${tag_value}" \
                "Name=instance-state-name,Values=pending,running" \
      --query 'Reservations[].Instances[0].{PrivateIpAddress:PrivateIpAddress, InstanceId:InstanceId}' \
      --output json 2>/dev/null || true
  )

  # Use jq to safely access the properties
  private_ip=$(jq -r '.[].PrivateIpAddress // "None"' <<<"$INSTANCE_DATA")
  instance_id=$(jq -r '.[].InstanceId // "None"' <<<"$INSTANCE_DATA")

  if [[ "$private_ip" != "None" && -n "$private_ip" ]]; then
    # Return both private_ip and instance_id in JSON
    echo "{\"private_ip\":\"${private_ip}\", \"instance_id\":\"${instance_id}\"}"
    exit 0
  fi

  if (( $(date +%s) > deadline )); then
    echo "Timed out waiting for instance with tag ${tag_key}=${tag_value} to have a private IP" >&2
    exit 1
  fi

  sleep "$sleep_s"
done
