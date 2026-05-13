# PR 스캔 가이드

SonarQube PR 분석 파라미터:

- `sonar.pullrequest.key`
- `sonar.pullrequest.branch`
- `sonar.pullrequest.base`

예시:

```bash
sonar-scanner \
  -Dsonar.pullrequest.key=${CI_MERGE_REQUEST_IID} \
  -Dsonar.pullrequest.branch=${CI_COMMIT_REF_NAME} \
  -Dsonar.pullrequest.base=${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}
```

GitLab MR decoration:

1. SonarQube DevOps Platform Integration에서 GitLab 연결
2. Project Settings에서 MR decoration 활성화
3. Jenkins 파이프라인에서 PR 파라미터를 scanner에 전달
