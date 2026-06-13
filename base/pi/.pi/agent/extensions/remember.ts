/**
 * Remember Extension
 *
 * Adds a /remember command that appends preferences to ~/.pi/agent/AGENTS.md
 * 
 * Usage:
 * - /remember prefer tabs over spaces
 * - /remember use conventional commits
 * - /remember avoid echo >> for daily notes, use sed
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { promises as fs } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("remember", {
    description: "Add a preference to global AGENTS.md",
    handler: async (args, ctx) => {
      const preference = args.trim();
      
      if (!preference) {
        ctx.ui.notify("Usage: /remember <preference>", "error");
        return;
      }

      try {
        const agentsPath = join(homedir(), ".pi", "agent", "AGENTS.md");
        
        // Read current content
        let content = "";
        try {
          content = await fs.readFile(agentsPath, "utf-8");
        } catch (error: any) {
          if (error.code !== "ENOENT") {
            throw error;
          }
          // File doesn't exist, create basic structure
          content = "# Global Agent Instructions\n\n## Preferences\n\n<!-- Preferences added via /remember will be appended below this line -->\n\n";
        }

        // Find the preferences section
        const preferencesMarker = "<!-- Preferences added via /remember will be appended below this line -->";
        const markerIndex = content.indexOf(preferencesMarker);
        
        if (markerIndex === -1) {
          // No marker found, add to end
          const newPreference = `\n- ${preference}\n`;
          content = content.trimEnd() + newPreference;
        } else {
          // Insert after marker
          const insertPoint = markerIndex + preferencesMarker.length;
          const before = content.slice(0, insertPoint);
          const after = content.slice(insertPoint);
          content = before + `\n\n- ${preference}` + after;
        }

        // Write back to file
        await fs.writeFile(agentsPath, content, "utf-8");
        
        ctx.ui.notify(`Added to AGENTS.md: "${preference}"`, "info");
        
      } catch (error: any) {
        ctx.ui.notify(`Failed to update AGENTS.md: ${error.message}`, "error");
      }
    },
  });
}