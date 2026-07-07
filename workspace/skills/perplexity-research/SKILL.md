---
name: perplexity-research
description: "Web research via Perplexity Sonar (LLM с доступом к интернету). Use when the operator says: «ресёрч», «поищи в интернете», «что говорят про X», «актуально ли», «факт-чек», «найди источники», «тренды», «best practices», «research X», «fact-check». Идеально для cross-source вопросов, трендов, сравнений, свежих новостей. Do NOT use for: чтение одного известного URL (markdown-new) или YouTube-видео (youtube-transcript)."
---

# Perplexity Research — веб-поиск

Ищи в интернете, проверяй факты, разбирай тренды и находи свежие источники через
Perplexity Sonar API. Perplexity сам обходит много источников и возвращает связный
ответ со ссылками.

## Ключ API

Ключ (`pplx-...`) лежит в файле:

```
__SECRETS__/perplexity-api-key
```

Если файла нет — значит ключ ещё не подключён. Скажи об этом оператору и дай
ссылку: получить ключ на https://www.perplexity.ai/settings/api, затем положить в
этот файл (`chmod 600`). Подробно — в `docs/SETUP-KEYS.md`. Без ключа отвечай из
своих знаний, но честно предупреди, что это без свежего веб-поиска.

## Как использовать

Когда оператор просит поискать, проверить факт или узнать свежее:

```bash
PPLX_KEY=$(cat __SECRETS__/perplexity-api-key)
curl -sS --max-time 40 -X POST "https://api.perplexity.ai/chat/completions" \
  -H "Authorization: Bearer $PPLX_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "sonar",
    "messages": [
      {"role": "user", "content": "ВОПРОС ОПЕРАТОРА"}
    ]
  }'
```

Ответ — в `.choices[0].message.content`. Верни его оператору своими словами,
сохрани ссылки-источники, которые Perplexity проставляет в тексте ([1], [2], …).

## Модели

- `sonar` — базовая, дёшево (меньше рубля за запрос). Бери по умолчанию.
- `sonar-pro` — глубже, больше источников. Только когда нужен серьёзный разбор.

## Когда использовать

- Свежие новости, события, тренды.
- Best practices и рекомендации.
- Факт-чек утверждений.
- Сравнение технологий/сервисов, анализ рынка.

## Когда НЕ использовать

- Чтение одного известного URL → навык `markdown-new`.
- YouTube-видео → навык `youtube-transcript`.
