;;; emanix-openrouter-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'emanix-openrouter)

(ert-deftest emanix-openrouter-summarize ()
  "7-day window + today's daily usage when activity lags; monthly total."
  (let* ((now (encode-time (iso8601-parse "2026-07-07T12:00:00Z")))
         (activity '(((date . "2026-07-05 00:00:00") (usage . 1.25)
                      (requests . 10) (model . "anthropic/claude-sonnet-5"))
                     ;; outside the 7-day window — excluded
                     ((date . "2026-06-20 00:00:00") (usage . 9.0)
                      (requests . 4) (model . "old/model"))))
         (key-data '((usage_daily . 0.75) (usage_monthly . 3.5)))
         (out (emanix-openrouter--summarize activity key-data now)))
    ;; 1.25 in-window + 0.75 daily (today missing from activity) = 2.00
    (should (string-match-p "\\$2\\.00 — last 7 days (10 requests)" out))
    (should (string-match-p "Models: anthropic/claude-sonnet-5" out))
    (should-not (string-match-p "old/model" out))
    (should (string-match-p "\\$3\\.50 — this month" out))))

(ert-deftest emanix-openrouter-summarize-no-double-count-today ()
  "When today IS in the activity data, usage_daily is not added again."
  (let* ((now (encode-time (iso8601-parse "2026-07-07T12:00:00Z")))
         (activity '(((date . "2026-07-07 00:00:00") (usage . 2.0)
                      (requests . 5) (model . "anthropic/claude-sonnet-5"))))
         (key-data '((usage_daily . 2.0) (usage_monthly . 2.0)))
         (out (emanix-openrouter--summarize activity key-data now)))
    (should (string-match-p "\\$2\\.00 — last 7 days (5 requests)" out))))
