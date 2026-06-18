// Deployment configuration.
// After deploying the Google Apps Script web app (see README), paste its URL here.
// While ENDPOINT_URL is empty, answers are kept in localStorage only and can be
// downloaded as JSON from the completion screen.
window.TGSR_CONFIG = {
  ENDPOINT_URL: "https://script.google.com/macros/s/AKfycbyjKDc4kJXCMdDH1WKFNjuTybkYjW6p96SSOex3QW_Ms-GVjYUn2WMIchVPuvsAX8SqIA/exec",
  STUDY_ID: "tgsr_mmau_speech_v5", // v2: Q1 4-point; v3: Q2 reworded; v4: Q3 added; v5: Q3 -> 1-5 Likert
  // Which manifest to serve: "items_subset.json" (10 diverse clips <=15s) or
  // "items.json" (all 66). Generate the subset with select_subset.ps1.
  ITEMS_FILE: "items_subset.json",
};
