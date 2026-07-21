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

  // Mounted on the due-date input. Some mobile browsers (notably iOS
  // Safari) default an EMPTY date picker's wheel to today the instant it
  // opens, and fire a real `input`/`change` event for that default before
  // the user has touched anything — which phx-change would otherwise save
  // as if the user had picked today. A genuine tap-to-select physically
  // can't land faster than this: focus, render the picker UI, then
  // register a touch is well over the threshold below. Listening in the
  // capture phase means this runs before LiveView's own (bubble-phase,
  // document-delegated) phx-change listener ever sees the event.
  DueDateGuard: {
    mounted() {
      this.focusedAt = 0;
      this.hadValue = false;
      this.valueAtFocus = "";

      this.el.addEventListener("focus", () => {
        this.focusedAt = performance.now();
        this.hadValue = this.el.value !== "";
        this.valueAtFocus = this.el.value;
      });

      const guard = (e) => {
        if (this.hadValue) return;
        if (performance.now() - this.focusedAt >= 400) return;

        this.el.value = this.valueAtFocus;
        e.preventDefault();
        e.stopImmediatePropagation();
      };
      this.el.addEventListener("input", guard, true);
      this.el.addEventListener("change", guard, true);
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
