const recordForm = document.querySelector("#item-form");
const recordInput = document.querySelector("#item-name");
const recordList = document.querySelector("#item-list");
const emptyState = document.querySelector("#empty-state");
const formMessage = document.querySelector("#form-message");
const refreshButton = document.querySelector("#refresh-button");
const submitButton = document.querySelector("#submit-button");

function showFormMessage(message, tone) {
  formMessage.textContent = message;
  formMessage.classList.toggle("error", tone === "error");
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

function createRecordEntry(record) {
  const recordEntry = document.createElement("li");
  recordEntry.className = "item";

  const recordIndex = document.createElement("span");
  recordIndex.className = "item-index";
  recordIndex.textContent = `#${record.id}`;

  const recordName = document.createElement("span");
  recordName.className = "item-name";
  recordName.textContent = record.name;

  const createdAt = document.createElement("time");
  createdAt.dateTime = record.created_at;
  createdAt.textContent = formatDate(record.created_at);

  recordEntry.append(recordIndex, recordName, createdAt);
  return recordEntry;
}

function renderItems(records) {
  recordList.replaceChildren();
  emptyState.hidden = records.length > 0;
  emptyState.textContent = records.length ? "" : "还没有记录，先新增一条吧。";

  for (const record of records) recordList.append(createRecordEntry(record));
}

async function loadItems() {
  refreshButton.disabled = true;
  emptyState.hidden = false;
  emptyState.textContent = "正在加载数据...";

  try {
    const response = await fetch("/api/items");
    if (!response.ok) throw new Error("load failed");
    renderItems(await response.json());
  } catch (_error) {
    emptyState.hidden = false;
    emptyState.textContent = "数据加载失败，请稍后重试。";
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
  showFormMessage("正在保存...", "default");

  try {
    await saveRecord(recordName);
    recordInput.value = "";
    showFormMessage("保存成功", "default");
    await loadItems();
  } catch (error) {
    showFormMessage(error.message || "保存失败，请稍后重试。", "error");
  } finally {
    submitButton.disabled = false;
  }
}

recordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const recordName = recordInput.value.trim();
  if (!recordName) return;

  await submitRecord(recordName);
});

refreshButton.addEventListener("click", loadItems);
loadItems();
