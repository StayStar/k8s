const form = document.querySelector("#item-form");
const input = document.querySelector("#item-name");
const list = document.querySelector("#item-list");
const emptyState = document.querySelector("#empty-state");
const formMessage = document.querySelector("#form-message");
const refreshButton = document.querySelector("#refresh-button");
const submitButton = document.querySelector("#submit-button");
const recordCount = document.querySelector("#record-count");
const lastUpdated = document.querySelector("#last-updated");
const apiStatus = document.querySelector("#api-status");
const apiStatusText = document.querySelector("#api-status-text");

function showMessage(message, tone) {
  formMessage.textContent = message;
  formMessage.classList.toggle("error", tone === "error");
}

function setApiStatus(state, message) {
  apiStatus.classList.toggle("is-ready", state === "ready");
  apiStatus.classList.toggle("is-error", state === "error");
  apiStatusText.textContent = message;
}

function formatDate(isoTimestamp) {
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date(isoTimestamp));
}

function updateMetrics(records) {
  recordCount.textContent = records.length;
  lastUpdated.textContent = new Intl.DateTimeFormat("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date());
}

function renderItems(records) {
  list.replaceChildren();
  emptyState.hidden = records.length > 0;
  emptyState.textContent = records.length ? "" : "还没有记录，先新增一条吧。";
  updateMetrics(records);

  for (const record of records) {
    const entry = document.createElement("li");
    entry.className = "item";

    const index = document.createElement("span");
    index.className = "item-index";
    index.textContent = `#${record.id}`;

    const name = document.createElement("span");
    name.className = "item-name";
    name.textContent = record.name;

    const createdAt = document.createElement("time");
    createdAt.dateTime = record.created_at;
    createdAt.textContent = formatDate(record.created_at);

    entry.append(index, name, createdAt);
    list.append(entry);
  }
}

async function loadItems() {
  refreshButton.disabled = true;
  emptyState.hidden = false;
  emptyState.textContent = "正在加载数据...";

  try {
    const response = await fetch("/api/items");
    if (!response.ok) throw new Error("load failed");
    renderItems(await response.json());
    setApiStatus("ready", "数据服务可用");
  } catch (_error) {
    emptyState.hidden = false;
    emptyState.textContent = "数据加载失败，请稍后重试。";
    recordCount.textContent = "--";
    lastUpdated.textContent = "--:--";
    setApiStatus("error", "数据服务不可用");
  } finally {
    refreshButton.disabled = false;
  }
}

async function saveRecord(recordName) {
  const response = await fetch("/api/items", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: recordName }),
  });
  const responseBody = await response.json();
  if (!response.ok) throw new Error(responseBody.message || "save failed");
}

async function submitRecord(recordName) {
  submitButton.disabled = true;
  showMessage("正在保存...", "default");

  try {
    await saveRecord(recordName);
    input.value = "";
    showMessage("保存成功，记录已写入持久化存储。", "default");
    await loadItems();
  } catch (error) {
    showMessage(error.message || "保存失败，请稍后重试。", "error");
  } finally {
    submitButton.disabled = false;
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const recordName = input.value.trim();
  if (!recordName) return;

  await submitRecord(recordName);
});

refreshButton.addEventListener("click", loadItems);
loadItems();
