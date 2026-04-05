import { queryLinkByUrl, createLinkPage, updateLinkPage, getNotionPageUrl } from "../../lib/notion";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ message: "Method not allowed" });
  }

  try {
    const { url, title, category, desc, source, remarks, tags } = req.body;

    if (!url) {
      return res.status(400).json({ message: "連結不能為空" });
    }

    // 檢查重複
    const existingRecord = await queryLinkByUrl(url);

    if (existingRecord) {
      // 重複 - 更新現有記錄
      const linkData = {
        title,
        category,
        desc,
        source: source || "手動粘貼",
        remarks,
        tags: tags || [],
        provider: source || "",
      };

      await updateLinkPage(existingRecord.id, linkData);

      // 取得現有記錄的舊標題
      const oldTitle = existingRecord.properties?.["链接名称"]?.title?.[0]?.plain_text || title;

      return res.status(200).json({
        isUpdate: true,
        pageUrl: getNotionPageUrl(existingRecord.id),
        pageId: existingRecord.id,
        oldTitle,
        message: "已更新現有記錄",
      });
    } else {
      // 新記錄 - 建立
      const linkData = {
        url,
        title,
        category,
        desc,
        source: source || "手動粘貼",
        remarks,
        tags: tags || [],
        provider: source || "",
      };

      const newPage = await createLinkPage(linkData);

      return res.status(200).json({
        isUpdate: false,
        pageUrl: getNotionPageUrl(newPage.id),
        pageId: newPage.id,
        message: "已建立新記錄",
      });
    }
  } catch (error) {
    console.error("Save link error:", error);
    return res.status(500).json({
      message: error.message || "保存失敗，請檢查設定",
    });
  }
}
