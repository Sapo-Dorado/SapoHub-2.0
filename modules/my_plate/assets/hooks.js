// LiveView JS hooks contributed by the my_plate module.
// Nix composes every enabled module's hooks into core's bundle
// (core/assets/js/module_hooks.js) for releases; `mix sapo.gen.hooks`
// does the same for dev. Keep hooks framework-free so the future
// Capacitor app can reuse them.
//
// Vendors SortableJS (MIT, same version already proven in v1) rather
// than reinventing drag-and-drop — core doesn't provide a shared sortable
// library, so this is scoped entirely to the module.
import Sortable from "./vendor/sortable.js";

export default {
  // Mounted on the add-task title input. Native `autofocus` only fires on
  // first insertion in some browsers and never selects existing text, so
  // this hook does both explicitly whenever the input (re)appears.
  AutoSelect: {
    mounted() {
      this.el.focus();
      this.el.select();
    },
  },

  // TEMP diagnostic — mounted on the due-date input. Logs every raw
  // input/change DOM event straight to the server (via a no-op
  // "due_date_debug" event) so we can see what the browser actually fires
  // when the native picker's Reset is pressed, independent of whether it
  // ends up reaching save_due_date's phx-change binding at all.
  DueDateDebug: {
    mounted() {
      const log = (e) => {
        this.pushEvent("due_date_debug", { type: e.type, value: this.el.value });
      };
      this.el.addEventListener("input", log);
      this.el.addEventListener("change", log);
    },
  },

  // Mounted on each priority section's task list. `data-group` is the
  // priority name ("high"/"medium"/"low"); dragging a task into a
  // different section's list re-parents it there. On drop, pushes
  // "reorder" with the same {task_id, new_priority, new_position} shape
  // MyPlate.reorder_task/3 already expects (ported from v1's contract).
  TaskSortable: {
    mounted() {
      this.sortable = new Sortable(this.el, {
        group: "my-plate-tasks",
        handle: ".drag-handle",
        delay: 150,
        delayOnTouchOnly: true,
        animation: 150,
        // Without this, Sortable defers to the browser's native HTML5
        // drag-and-drop, whose floating "drag image" is painted by the
        // browser's own compositor — not a DOM node, so no CSS class we
        // toggle (e.g. hiding the empty-state text below it) can ever
        // affect it; it will always render on top of literally everything.
        // forceFallback swaps that out for Sortable's own JS-driven clone,
        // which is a real, ordinary DOM element we can see, size, and
        // style like anything else.
        forceFallback: true,
        fallbackOnBody: true,
        fallbackClass: "task-fallback",
        ghostClass: "task-ghost",
        chosenClass: "task-chosen",
        dragClass: "task-drag",
        // A drag can land in ANY priority section's list, not just the one
        // it started in, so "is a drag in progress" has to be tracked
        // globally (a body class) rather than per-instance — each section
        // mounts its own independent Sortable, and the empty-state message
        // in a *different* section needs to react too (it would otherwise
        // visually collide with the drag ghost/placeholder landing on top
        // of it, since that container has to stay transparent-ish to look
        // empty).
        onStart: () => document.body.classList.add("my-plate-dragging"),
        onEnd: (evt) => {
          document.body.classList.remove("my-plate-dragging");
          this.pushEvent("reorder", {
            task_id: evt.item.dataset.id,
            new_priority: evt.to.dataset.group,
            new_position: evt.newIndex,
          });
        },
      });
    },
    destroyed() {
      this.sortable?.destroy();
    },
  },
};
