const path = require("path");
const fs = require("fs");
const crypto = require("crypto");

/** @type {import("./helper.extern").default} */
module.exports = {
  projectPath(p) {
    if (path.isAbsolute(p)) return p;
    return path.join(__dirname, "..", p);
  },
  dirHash(p) {
    const targetDir = this.projectPath(p);
    const contents = fs
      .readdirSync(targetDir, { withFileTypes: true, recursive: true })
      .map((f) => {
        if (f.isFile())
          return fs.readFileSync(path.join(f.path, f.name), "utf8");
        return undefined;
      })
      .filter((f) => f !== undefined)
      .join("");

    return crypto.createHash("md5").update(contents).digest("hex");
  },
};
