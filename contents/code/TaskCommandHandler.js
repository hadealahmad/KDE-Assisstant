/*
 * KDE Assistant — TaskCommandHandler.js
 * Pure helper functions for task command processing
 */

.pragma library
.import "Database.js" as Db

/**
 * Check if a task title is a placeholder that should be ignored.
 * @param {string} title
 * @returns {boolean}
 */
function isPlaceholderTitle(title) {
    if (!title) return true;
    var lower = title.trim().toLowerCase();
    return lower === "title" || lower === "task title" || lower === "task name";
}

/**
 * Build task options from a command tag.
 * @param {Object} cmdTag - parsed command tag from TextHelpers
 * @param {string} sessionId
 * @param {Object} db - database handle
 * @returns {Object|null} task options or null if invalid
 */
function buildTaskOptions(cmdTag, sessionId, db) {
    var taskOpts = { sessionId: sessionId };

    if (cmdTag.type === "add_task") {
        if (cmdTag.group && cmdTag.group.trim() !== "") {
            var groupName = cmdTag.group.trim();
            var existingGroup = Db.findTaskGroupByName(db, groupName);
            if (existingGroup) {
                taskOpts.groupId = existingGroup.id;
            } else {
                var newGroupId = Db.createTaskGroup(db, groupName);
                taskOpts.groupId = newGroupId;
            }
        }
        taskOpts.description = cmdTag.description || "";
        taskOpts.priority = cmdTag.priority || 0;
        taskOpts.recurrence = cmdTag.recurrence || "";
        if (cmdTag.due && cmdTag.due.trim() !== "") {
            var dueDate = new Date(cmdTag.due);
            if (!isNaN(dueDate.getTime())) {
                taskOpts.dueDate = dueDate.getTime();
            }
        }
    }

    return taskOpts;
}

/**
 * Build a human-readable task details string for confirmation.
 * @param {string} taskTitle
 * @param {Object} taskOpts - task options
 * @param {Object} db - database handle
 * @returns {string} formatted task details
 */
function buildTaskDetailsString(taskTitle, taskOpts, db) {
    var details = "**" + taskTitle + "**";

    if (taskOpts.groupId) {
        var grpName = "";
        var currentGroups = Db.loadTaskGroups(db);
        for (var gi = 0; gi < currentGroups.length; gi++) {
            if (currentGroups[gi].id === taskOpts.groupId) {
                grpName = currentGroups[gi].name;
                break;
            }
        }
        if (grpName) details += "\nGroup: " + grpName;
    }

    if (taskOpts.priority && taskOpts.priority > 0) {
        var pLabel = taskOpts.priority === 3 ? "High" : taskOpts.priority === 2 ? "Medium" : "Low";
        details += "\nPriority: " + pLabel;
    }

    if (taskOpts.dueDate) {
        var dd = new Date(taskOpts.dueDate);
        details += "\nDue: " + dd.toLocaleDateString();
    }

    if (taskOpts.description) {
        details += "\n" + taskOpts.description;
    }

    return details;
}

/**
 * Filter task tags to only include those not already recently created.
 * @param {Array} taskTags - array of parsed command tags
 * @param {Array} recentlyCreatedTitles - lowercase titles already created
 * @returns {Array} filtered tags
 */
function filterNewTasks(taskTags, recentlyCreatedTitles) {
    var filtered = [];
    for (var i = 0; i < taskTags.length; i++) {
        var t = (taskTags[i].title || "").trim().toLowerCase();
        if (t && recentlyCreatedTitles.indexOf(t) === -1) {
            filtered.push(taskTags[i]);
        }
    }
    return filtered;
}
