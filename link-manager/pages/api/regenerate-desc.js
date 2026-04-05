import { regenerateDesc } from "../../lib/claude";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ message: "Method not allowed" });
  }

  try {
    const { url, title, category, inputRaw } = req.body;

    if (!url) {
      return res.status(400).json({ message: "連結不能為空" });
    }

    const desc = await regenerateDesc(url, title, category, inputRaw);
    return res.status(200).json({ desc });
  } catch (error) {
    console.error("API error:", error);
    return res.status(500).json({
      message: error.message || "重新生成失敗",
    });
  }
}
