# today.json — contract v1

Published on GitHub Pages at `docs/today.json`. Written by `writer/build_today.py`
from TWSE OpenAPI `/exchangeReport/MI_INDEX` (open government data).

```json
{
  "v": 1,
  "source": "TWSE",
  "asOf": "2026-11-04T14:35:00+08:00",
  "index":  { "date": "2026-11-03", "name": "發行量加權股價指數",
              "close": 43307.54, "change": -1612.6, "changePct": -3.59 },
  "ticker": { "date": "2026-11-03", "items": [
              { "name": "半導體類指數", "close": 1446.44,
                "change": -45.17, "changePct": -3.03 } ] },
  "topic": null
}
```

| Field | Meaning |
|---|---|
| `v` | Contract version. Old store builds stay on phones, so clients read by `v` and ignore fields they do not know. Adding a field does not bump `v`. |
| `source` | Always `"TWSE"`. Every client shows it as "Source: TWSE". |
| `asOf` | When the writer fetched the data (Taipei time). Not the market date. |
| `index.date` | The trading date of the close, ISO. Carried by the index itself. |
| `index.close` | The close. Clients never truncate it. |
| `index.change`, `index.changePct` | Signed. Up positive, down negative, flat `0.0`. |
| `ticker.items` | The fixed list of sector indices in `writer/ticker.json`, in that order. A name TWSE no longer returns is skipped. |
| `topic` | `null` while no lead is published. Later `{ "date": "...", "lead": "..." }`. It carries its own date and may be empty. It has no title or URL: no publishable source exists. |

## Parsing notes (measured on the 2026-11-03 response, 267 rows)

- The date is ROC (`1151103` is 2026-11-03).
- `漲跌` holds `+` or `-` apart from the points. Points carry a thousands comma.
- `漲跌百分比` carries its own minus on a down day and no plus on an up day,
  so the writer takes the sign from `漲跌` only.
- `特殊處理註記` was empty in all 267 rows. Its non-empty form is unexplored.
- A flat day (`漲跌` neither `+` nor `-`) has not been observed. The writer treats
  it as zero change and fails loud when the sign is unknown but the points are not zero.
