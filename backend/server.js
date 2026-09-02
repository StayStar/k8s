const express = require("express");
const mysql = require("mysql2/promise");

const app = express();
const port = Number(process.env.PORT || 3000);

const dbConfig = {
  host: process.env.DB_HOST || "mysql",
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || "app",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "appdb",
  waitForConnections: true,
  connectionLimit: 5,
  queueLimit: 0,
};

const pool = mysql.createPool(dbConfig);

app.use(express.json());

async function initializeDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS items (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

app.get("/healthz", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok" });
  } catch (error) {
    console.error("Health check failed", error);
    res.status(503).json({ status: "error" });
  }
});

app.get("/api/items", async (_req, res) => {
  try {
    const [rows] = await pool.query(
      "SELECT id, name, created_at FROM items ORDER BY id DESC"
    );
    res.json(rows);
  } catch (error) {
    console.error("Item query failed", error);
    res.status(500).json({ message: "查询数据失败" });
  }
});

app.post("/api/items", async (req, res) => {
  const name = typeof req.body.name === "string" ? req.body.name.trim() : "";

  if (!name) {
    return res.status(400).json({ message: "名称不能为空" });
  }

  try {
    const [insertResult] = await pool.query("INSERT INTO items (name) VALUES (?)", [
      name,
    ]);
    const [rows] = await pool.query(
      "SELECT id, name, created_at FROM items WHERE id = ?",
      [insertResult.insertId]
    );
    res.status(201).json(rows[0]);
  } catch (error) {
    console.error("Item creation failed", error);
    res.status(500).json({ message: "新增数据失败" });
  }
});

initializeDatabase()
  .then(() => {
    app.listen(port, "0.0.0.0", () => {
      console.log(`Backend listening on port ${port}`);
    });
  })
  .catch((error) => {
    console.error("Database initialization failed", error);
    process.exit(1);
  });

process.on("SIGTERM", async () => {
  await pool.end();
  process.exit(0);
});
