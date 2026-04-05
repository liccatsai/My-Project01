// Notion API 工具函数

const NOTION_TOKEN = process.env.NOTION_TOKEN;
const NOTION_DATABASE_ID = process.env.NOTION_DATABASE_ID;
const NOTION_API_BASE = "https://api.notion.com/v1";

/**
 * 根据 URL 查询现有记录
 */
export async function queryLinkByUrl(url) {
  if (!NOTION_TOKEN || !NOTION_DATABASE_ID) {
    throw new Error("Notion credentials not configured");
  }

  try {
    const response = await fetch(`${NOTION_API_BASE}/databases/${NOTION_DATABASE_ID}/query`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${NOTION_TOKEN}`,
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        filter: {
          property: "URL",
          url: {
            equals: url,
          },
        },
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      console.error("Notion query error:", error);
      throw new Error(`Notion API error: ${error.message}`);
    }

    const data = await response.json();
    return data.results.length > 0 ? data.results[0] : null;
  } catch (error) {
    console.error("Error querying Notion:", error);
    throw error;
  }
}

/**
 * 创建新链接页面
 */
export async function createLinkPage(linkData) {
  if (!NOTION_TOKEN || !NOTION_DATABASE_ID) {
    throw new Error("Notion credentials not configured");
  }

  try {
    const properties = buildNotionProperties(linkData);

    const response = await fetch(`${NOTION_API_BASE}/pages`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${NOTION_TOKEN}`,
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        parent: {
          database_id: NOTION_DATABASE_ID,
        },
        properties,
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      console.error("Notion create error:", error);
      throw new Error(`Notion API error: ${error.message}`);
    }

    const data = await response.json();
    return data;
  } catch (error) {
    console.error("Error creating Notion page:", error);
    throw error;
  }
}

/**
 * 更新现有链接页面（重复时）
 */
export async function updateLinkPage(pageId, linkData) {
  if (!NOTION_TOKEN) {
    throw new Error("Notion credentials not configured");
  }

  try {
    const properties = buildNotionProperties(linkData);

    const response = await fetch(`${NOTION_API_BASE}/pages/${pageId}`, {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${NOTION_TOKEN}`,
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        properties,
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      console.error("Notion update error:", error);
      throw new Error(`Notion API error: ${error.message}`);
    }

    const data = await response.json();
    return data;
  } catch (error) {
    console.error("Error updating Notion page:", error);
    throw error;
  }
}

/**
 * 构建 Notion 页面属性对象
 */
function buildNotionProperties(linkData) {
  const properties = {
    "链接名称": {
      title: [
        {
          text: {
            content: linkData.title || linkData.url,
          },
        },
      ],
    },
    "userDefined:URL": {
      url: linkData.url,
    },
    "分类": {
      select: {
        name: linkData.category || "其他",
      },
    },
    "简述": {
      rich_text: [
        {
          text: {
            content: linkData.desc || "",
          },
        },
      ],
    },
    "来源渠道": {
      select: {
        name: linkData.source || "手动粘贴",
      },
    },
    "提供者": {
      rich_text: [
        {
          text: {
            content: linkData.provider || "",
          },
        },
      ],
    },
  };

  // 添加标签（如果有）
  if (linkData.tags && linkData.tags.length > 0) {
    properties["标签"] = {
      multi_select: linkData.tags.map((tag) => ({
        name: tag,
      })),
    };
  }

  // 添加备注（如果有）
  if (linkData.remarks) {
    properties["备注"] = {
      rich_text: [
        {
          text: {
            content: linkData.remarks,
          },
        },
      ],
    };
  }

  // 验证状态默认为 "待验证"
  properties["验证状态"] = {
    select: {
      name: "待验证",
    },
  };

  return properties;
}

/**
 * 获取 Notion 页面的公开链接
 */
export function getNotionPageUrl(pageId) {
  // Notion 页面 URL 格式：https://notion.so/{database_id}/{page_id}
  // 简化版本（不带 title）：https://notion.so/{page_id}
  return `https://notion.so/${pageId.replace(/-/g, "")}`;
}
