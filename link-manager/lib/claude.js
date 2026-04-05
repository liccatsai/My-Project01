// Claude API 工具函数

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;

export async function analyzeLink(inputRaw, existingTags = []) {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("Claude API key not configured");
  }

  try {
    const existingTagsList = existingTags.length ? existingTags.join("、") : "（尚無）";

    const prompt = `你是一個文件整理助理。使用者輸入了一段混合文字，其中包含一個雲端連結以及一些上下文描述。

請依序完成：
1. 提取連結 URL
2. 根據 URL 和使用者上下文，用繁體中文產出「title」（5-20字）
3. 生成「desc」兩段式簡述，格式：「[文件類型] — [具體用途說明]，[狀態或備註]」
4. 推測「category」，從以下選一個：美術、排程、會議紀錄、文件、試算表、簡報、資料夾、其他
5. 建議 2-4 個「tags」，優先從現有標籤選擇：${existingTagsList}
6. 識別「source」發話者：從輸入找出傳連結的人名，找不到則回傳空字串

使用者輸入：
${inputRaw}

最終只回傳 JSON，格式：{"url":"...","title":"...","desc":"...","category":"...","tags":["...","..."],"source":"..."}`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
      },
      body: JSON.stringify({
        model: "claude-opus-4-6",
        max_tokens: 2000,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      console.error("Claude API error:", error);
      throw new Error(`Claude API error: ${error.error?.message || "Unknown error"}`);
    }

    const data = await response.json();

    // 提取 text content
    const textContent = data.content
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("")
      .trim();

    // 清理 markdown 格式
    const clean = textContent.replace(/```json|```/g, "").trim();

    // 提取 JSON
    const jsonMatch = clean.match(/\{[\s\S]*\}(?=[^}]*$)/);
    const parsed = JSON.parse(jsonMatch ? jsonMatch[0] : clean);

    return parsed;
  } catch (error) {
    console.error("Error analyzing link:", error);
    throw error;
  }
}

/**
 * 重新生成简述
 */
export async function regenerateDesc(url, title, category, inputRaw) {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("Claude API key not configured");
  }

  try {
    const prompt = `你是一個文件整理助理。根據以下資訊，用繁體中文生成兩段式固定格式簡述。
格式：「[文件類型] — [具體用途說明]，[狀態或備註]」
範例：「簡報 — 2024 夏季新品上市活動提案，包含預算規劃與執行時程，審核中」

URL: ${url}
標題: ${title}
分類: ${category}
原始輸入（含上下文）: ${inputRaw}

只回覆簡述本身，不要任何前綴。`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
      },
      body: JSON.stringify({
        model: "claude-opus-4-6",
        max_tokens: 1000,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Claude API error: ${error.error?.message || "Unknown error"}`);
    }

    const data = await response.json();
    const text = data.content
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("")
      .trim();

    return text;
  } catch (error) {
    console.error("Error regenerating description:", error);
    throw error;
  }
}
