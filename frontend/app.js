const form = document.querySelector("#item-form");
const input = document.querySelector("#item-name");
const list = document.querySelector("#item-list");
const emptyState = document.querySelector("#empty-state");
const formMessage = document.querySelector("#form-message");
const refreshButton = document.querySelector("#refresh-button");

function showMessage(message, isError = false) {
  formMessage.textContent = message;
  formMessage.classList.toggle("error", isError);
}

function renderItems(records) {
  list.replaceChildren();
  emptyState.hidden = records.length > 0;
  emptyState.textContent = records.length ? "" : "还没有记录，先新增一条吧。";

  for (const record of records) {
    const entry = document.createElement("li");
    entry.className = "item";
    entry.innerHTML = `
      <span class="item-index">#${record.id}</span>
      <span class="item-name"></span>
      <time>${new Date(record.created_at).toLocaleString("zh-CN")}</time>
    `;
    entry.querySelector(".item-name").textContent = record.name;
    list.append(entry);
  }
}

async function loadItems() {
  emptyState.hidden = false;
  emptyState.textContent = "正在加载数据...";

  try {
    const response = await fetch("/api/items");
    if (!response.ok) throw new Error("load failed");
    renderItems(await response.json());
  } catch (_error) {
    emptyState.hidden = false;
    emptyState.textContent = "数据加载失败，请稍后重试。";
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const name = input.value.trim();
  if (!name) return;

  showMessage("正在保存...");
  try {
    const response = await fetch("/api/items", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });
    const responseBody = await response.json();
    if (!response.ok) throw new Error(responseBody.message || "save failed");
    input.value = "";
    showMessage("保存成功");
    await loadItems();
  } catch (error) {
    showMessage(error.message || "保存失败，请稍后重试。", true);
  }
});

refreshButton.addEventListener("click", loadItems);
loadItems();
