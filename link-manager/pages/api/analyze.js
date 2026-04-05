import { analyzeLink } from "../../lib/claude";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ message: "Method not allowed" });
  }

  try {
    const { inputRaw, existingTags } = req.body;

    if (!inputRaw) {
      return res.status(400).json({ message: "輸入不能為空" });
    }

    const result = await analyzeLink(inputRaw, existingTags || []);
    return res.status(200).json(result);
  } catch (error) {
    console.error("API error:", error);
    return res.status(500).json({
      message: error.message || "分析失敗，請重試",
    });
  }
}
