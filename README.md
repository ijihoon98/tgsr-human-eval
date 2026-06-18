# TGSR Human Evaluation (Q4: Grounded Reasoning Accuracy & Interpretability)

MMAU-mini-Speech의 타임스탬프 추론 출력에 대한 사람 평가 웹페이지.
GitHub Pages(정적 호스팅) + Google Apps Script → Google Sheets(응답 수집) 구조로, 서버가 필요 없습니다.

## 구성

| 파일 | 역할 |
|---|---|
| `index.html` | 소개 페이지 — task 설명 + 나이/학력(응답 거부 가능) 수집. 참가자 ID 자동 생성 |
| `eval.html` | 평가 UI — 파형 + 구간 하이라이트(wavesurfer.js). Q1 Referent Accuracy(Yes/Partially/No/Unsure), Q2 Helpfulness(Likert 1–5), Q3 Answer Supportiveness(Likert 1–5; Q1–Q2 답변 후 과제 컨텍스트와 함께 공개) |
| `config.js` | Apps Script 엔드포인트 URL 설정 |
| `items.json` | 평가 항목 manifest (66개, prepare 스크립트로 생성) |
| `audio/` | 평가용 wav (66개, 약 225MB) |
| `apps_script.gs` | Google Apps Script 백엔드 (Sheets에 응답 기록) |
| `prepare_items.py` / `prepare_items.ps1` | `*_highIoU.json` → `items.json` + `audio/` 생성 |
| `analyze_results.py` | 결과 분석 — Referent / Soft Referent Accuracy, Helpfulness, Supportiveness Score / Support Rate / Contradiction Rate, Fleiss' kappa |
| `serve_local.ps1` | 로컬 테스트용 정적 서버 (`http://localhost:8123`) |

## 배포 절차

### 1. Google Sheets + Apps Script (응답 수집)

1. [sheets.google.com](https://sheets.google.com)에서 새 스프레드시트 생성 (이름 예: `TGSR Human Eval`)
2. 메뉴 **확장 프로그램 > Apps Script** 클릭
3. `Code.gs` 내용을 지우고 이 repo의 `apps_script.gs` 내용을 붙여넣기 → 저장
4. 우측 상단 **배포 > 새 배포** → 유형: **웹 앱**
   - 실행 계정: **나**
   - 액세스 권한: **모든 사용자** (annotator가 로그인 없이 제출하려면 필수)
5. 처음 배포 시 권한 승인 (본인 계정 → "고급" → "안전하지 않은 페이지로 이동" → 허용)
6. 발급된 **웹 앱 URL**(`https://script.google.com/macros/s/.../exec`)을 복사
7. 브라우저로 그 URL을 열어 `{"ok":true,...}`가 보이면 정상

### 2. config.js에 엔드포인트 입력

```js
ENDPOINT_URL: "https://script.google.com/macros/s/XXXX/exec",
```

### 3. GitHub repo 생성 + Pages 배포

```powershell
cd tgsr_human_eval
git init
git add .
git commit -m "TGSR human evaluation site"
# github.com에서 public repo 생성 (예: tgsr-human-eval) 후:
git remote add origin https://github.com/<username>/tgsr-human-eval.git
git branch -M main
git push -u origin main
```

GitHub repo 페이지에서 **Settings > Pages > Source: Deploy from a branch / Branch: main, / (root)** 선택.
1~2분 뒤 `https://<username>.github.io/tgsr-human-eval/` 에서 접속 가능.

> 주의: 오디오 약 225MB가 포함되므로 첫 push에 시간이 걸립니다. repo는 public이어야
> 무료 Pages가 가능하며, MMAU 오디오가 공개되는 점을 감안해 평가 종료 후 repo를
> 삭제하거나 private으로 전환하는 것을 권장합니다.

### 4. Annotator에게 링크 공유

- 기본: `https://<username>.github.io/tgsr-human-eval/` 만 공유. 참가자 ID는 소개
  페이지에서 **자동 생성**되어 브라우저에 저장됩니다(별도 입력 불필요). 같은 브라우저로
  다시 접속하면 동일 ID로 이어서 평가됩니다.
- 코디네이터가 ID를 직접 지정하고 싶으면 `.../index.html?annotator=A1`(또는
  `.../eval.html?annotator=A1`)처럼 링크에 넣으면 자동 ID 대신 그 값이 사용됩니다.

진행 상태는 브라우저 localStorage에 저장되므로 **같은 브라우저**에서 이어서 평가할 수 있습니다.
완료 화면에서 JSON 백업 다운로드가 가능하고, 업로드 실패분은 자동 재시도/수동 재시도됩니다.

## 결과 분석

Google Sheets에서 **파일 > 다운로드 > CSV** 후:

```bash
python analyze_results.py responses.csv
# 또는 JSON 백업으로:
python analyze_results.py tgsr_answers_A1.json tgsr_answers_A2.json
```

출력 (unsure는 모든 비율의 분모에서 제외):

- **Task A — Referent Accuracy** = Yes / (Yes + Partially + No),
  **Soft Referent Accuracy** = (Yes + 0.5 × Partially) / (Yes + Partially + No)
- **Task B — Helpfulness** 평균 (전체 / yes / partially / no)
- **Task C — Supportiveness Score** = Likert 1–5 평균
  (1 Contradicts / 2 Does not support / 3 Neutral / 4 Somewhat / 5 Strongly supports),
  **Support Rate** = 4점 이상 비율, **Contradiction Rate** = 1점 비율,
  referent 판정(yes/partially/no)별 Support Rate — "정확히 grounding된 timestamp가
  답을 실제로 지지하는 근거인가"를 직접 보여주는 분해
- annotator별 분해, Fleiss' kappa(2인 이상 중복 평가 항목 기준)

## 평가 항목 재생성

원본 평가 JSON이나 추출 규칙이 바뀌면:

```powershell
.\prepare_items.ps1 -InputJson ..\<eval>.json -AudioDir ..\test-mini-audios
# 또는 Python:
python prepare_items.py --input ../<eval>.json --audio-dir ../test-mini-audios
```

기본값: 출력(output)당 타임스탬프 포함 reasoning step 1개를 시드 고정 랜덤 샘플링
(`--all-steps`로 전체 추출 가능). 타임스탬프 패턴: `From <X>(s|seconds) to <Y>(s|seconds)`.

## 로컬 테스트

```powershell
.\serve_local.ps1            # http://localhost:8123 에서 서빙
```

`file://`로 직접 열면 `fetch(items.json)`이 차단되므로 반드시 서버를 통해 열어야 합니다.
