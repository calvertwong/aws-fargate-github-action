import express from "express";

const app = express();

app.get("/healthcheck", (req, res) => {
  const healthcheck = {
    app: "dummy node",
    uptime: process.uptime(),
    message: "OK",
    timestamp: Date.now(),
  };

  try {
    res.send(healthcheck);
  } catch (error) {
    healthcheck.message = error;
    res.status(503).send();
  }
});

app.listen(3001, () => console.log("Server started..."));
