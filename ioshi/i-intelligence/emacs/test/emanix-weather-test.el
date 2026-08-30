;;; emanix-weather-test.el --- ERT tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'emanix-weather)

(ert-deftest emanix-weather-format-periods ()
  "Formats NWS hourly periods: local time, temp, precip %, short forecast."
  (let* ((json "{\"periods\":[
{\"startTime\":\"2026-07-07T15:00:00-04:00\",\"temperature\":78,
 \"probabilityOfPrecipitation\":{\"value\":40},\"shortForecast\":\"Chance Showers\"},
{\"startTime\":\"2026-07-07T16:00:00-04:00\",\"temperature\":77,
 \"probabilityOfPrecipitation\":{\"value\":null},\"shortForecast\":\"Sunny\"}]}")
         (periods (alist-get 'periods
                             (json-parse-string json :object-type 'alist
                                                 :array-type 'list
                                                 :null-object nil)))
         (out (emanix-weather--format-periods periods t))) ; zone t = UTC
    ;; 15:00-04:00 is 19:00 UTC
    (should (string-match-p "Tue 7PM" out))
    (should (string-match-p "78°" out))
    (should (string-match-p "40%" out))
    (should (string-match-p "Chance Showers" out))
    ;; null precip probability renders as 0%
    (should (string-match-p "0%" out))
    (should (= 2 (length (split-string out "\n"))))))

(ert-deftest emanix-weather-format-periods-caps-at-8 ()
  (let* ((period '((startTime . "2026-07-07T15:00:00-04:00") (temperature . 70)
                   (probabilityOfPrecipitation . ((value . 0)))
                   (shortForecast . "Clear")))
         (out (emanix-weather--format-periods (make-list 12 period) t)))
    (should (= 8 (length (split-string out "\n"))))))
