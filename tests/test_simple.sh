#!/bin/bash

# 테스트 JSON 파일 생성
json_file="/tmp/test_gateway_$$.json"
cat > "$json_file" << 'EOF'
{
  "data": [
    {"hostname":"server1","ssh_host":"10.0.0.1","ssh_user":"user1","ssh_port":22,"ssh_key_path":"","ssh_password":"pass1","lssn":1},
    {"hostname":"server2","ssh_host":"10.0.0.2","ssh_user":"user2","ssh_port":22,"ssh_key_path":"","ssh_password":"pass2","lssn":2}
  ]
}
EOF

echo "1. JSON 파일 생성: $json_file"
echo ""

# 배열 선언
declare -a server_list

# 임시 파일에서 읽기
temp_file="/tmp/servers_$$.jsonl"
echo "2. jq로 파싱 중..."
jq -c '.data[]?' "$json_file" > "$temp_file"

echo "임시 파일 내용:"
cat "$temp_file"
echo ""

echo "3. 배열에 저장 중..."
while IFS= read -r server_json; do
    [ -z "$server_json" ] && continue
    server_list+=("$server_json")
    echo "   ✓ 저장됨: $(echo "$server_json" | jq -r '.hostname')"
done < "$temp_file"

rm -f "$temp_file"
echo ""

echo "4. 배열 크기: ${#server_list[@]}"
echo ""

echo "5. For loop 시작:"
count=0
for item in "${server_list[@]}"; do
    ((count++))
    hostname=$(echo "$item" | jq -r '.hostname')
    echo "   [$count] $hostname"
done

echo ""
echo "6. 처리된 서버: $count개"

rm -f "$json_file"
