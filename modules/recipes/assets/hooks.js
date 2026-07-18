// LiveView JS hooks contributed by the recipes module (composed into
// core's bundle by nix). Kept framework-free, same convention as
// my_plate's hooks.js.

const REVEAL_PX = 64; // how far the front card slides to fully reveal the "add" action
const TRIGGER_PX = 40; // drag distance past which releasing counts as a swipe-add

export default {
  // Mounted on each ingredient row in the recipe-detail view
  // (`data-id` = the recipe_ingredient id). Dragging the row left reveals
  // an "add to shopping list" action; releasing past TRIGGER_PX pushes
  // the same "add_ingredient" event the row's persistent tap button
  // sends — swipe is an accelerator, never the only way to add an
  // ingredient (poor discoverability on desktop/first use otherwise).
  SwipeToAdd: {
    mounted() {
      this.front = this.el.querySelector("[data-swipe-front]");
      this.startX = null;
      this.dx = 0;

      this.onPointerDown = (e) => {
        if (e.pointerType === "mouse" && e.button !== 0) return;
        this.startX = e.clientX;
        this.dx = 0;
        this.front.style.transition = "none";
      };

      this.onPointerMove = (e) => {
        if (this.startX === null) return;
        this.dx = Math.min(0, Math.max(-REVEAL_PX, e.clientX - this.startX));
        this.front.style.transform = `translateX(${this.dx}px)`;
      };

      this.onPointerUp = () => {
        if (this.startX === null) return;
        this.front.style.transition = "transform 150ms ease-out";

        if (this.dx <= -TRIGGER_PX) {
          this.pushEvent("add_ingredient", { id: this.el.dataset.id });
        }

        this.front.style.transform = "translateX(0px)";
        this.startX = null;
        this.dx = 0;
      };

      this.el.addEventListener("pointerdown", this.onPointerDown);
      this.el.addEventListener("pointermove", this.onPointerMove);
      this.el.addEventListener("pointerup", this.onPointerUp);
      this.el.addEventListener("pointercancel", this.onPointerUp);

      // Server confirms an add (from either the swipe above or the plain
      // tap button, which has no JS of its own) by pushing this event —
      // one visual acknowledgment regardless of which affordance was used.
      this.handleEvent("ingredient_added", (payload) => {
        if (payload.id !== this.el.dataset.id) return;
        this.el.classList.add("recipes-row-added-flash");
        setTimeout(() => this.el.classList.remove("recipes-row-added-flash"), 600);
      });
    },
    destroyed() {
      this.el.removeEventListener("pointerdown", this.onPointerDown);
      this.el.removeEventListener("pointermove", this.onPointerMove);
      this.el.removeEventListener("pointerup", this.onPointerUp);
      this.el.removeEventListener("pointercancel", this.onPointerUp);
    },
  },

  // Mounted on a combobox's text input. Auto-focuses when it (re)appears
  // (e.g. after clicking "+ add an item…" to reveal it), same rationale
  // as my_plate's AutoSelect hook.
  ComboboxAutoFocus: {
    mounted() {
      this.el.focus();
    },
  },
};
