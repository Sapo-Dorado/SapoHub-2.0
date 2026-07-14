// LiveView JS hooks for the Projects module — framework-free (Sortable is
// vendored, same pattern as my_plate's TaskSortable).
import Sortable from "./vendor/sortable.js";

const ProjectSortable = {
  mounted() {
    this.sortable = null;
    this.applySortState();
  },
  updated() {
    this.applySortState();
  },
  applySortState() {
    const sorting = this.el.dataset.sorting === "true";

    if (sorting && !this.sortable) {
      this.sortable = Sortable.create(this.el, {
        handle: ".drag-handle",
        animation: 150,
        onEnd: () => {
          const ids = Array.from(this.el.children).map((el) => el.dataset.id);
          this.pushEvent("reorder_projects", { ids });
        },
      });
    } else if (!sorting && this.sortable) {
      this.sortable.destroy();
      this.sortable = null;
    }
  },
  destroyed() {
    if (this.sortable) this.sortable.destroy();
  },
};

const ScrollBottom = {
  updated() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

export default { ProjectSortable, ScrollBottom };
