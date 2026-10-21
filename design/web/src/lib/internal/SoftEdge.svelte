<script lang="ts" module>
  /** Where a soft edge sits around its header or footer. */
  export type SoftEdgeShape = "screen" | "sheet";
</script>

<script lang="ts">
  interface Props {
    edge: "top" | "bottom";
    /** The header or footer's height in px, its safe area included. 0 for none. */
    control: number;
    /** The safe area inside the control, as a CSS length. */
    inset?: string;
    /** Whether hidden content lies beyond this edge. Fades in and out. */
    active: boolean;
    /** Scrollbar width in px, kept clear of the soft edge. */
    gutter?: number;
    shape?: SoftEdgeShape;
  }

  const { edge, control, inset = "0px", active, gutter = 0, shape = "screen" }: Props = $props();

  /* Screens keep the blur tight to the control. Sheets, whose header carries a
     description, reach further so text beneath it doesn't stay legible.
     fullDepth: how far down the control the blur stays full. overhang and
     fadeReach: how far blur and fade reach past the control, in px. Matches
     iOS SoftEdgeShape. */
  const SHAPES = {
    screen: { fullDepth: 0.4, overhang: 16, fadeReach: 40 },
    sheet: { fullDepth: 1, overhang: 44, fadeReach: 52 },
  };

  /* The fade: the surface at FADE_STRENGTH · (1 − x)^FADE_CURVE, x from the
     screen edge to the end of the soft edge. Light, as the blur does most of
     the hiding. */
  const FADE_STRENGTH = 0.5;
  const FADE_CURVE = 1.6;
  const STEPS = 32; // matches iOS SoftEdgeCurve.steps

  const fadeStops = Array.from({ length: STEPS + 1 }, (_, i) => {
    const x = i / STEPS;
    const coverage = (FADE_STRENGTH * Math.pow(1 - x, FADE_CURVE) * 100).toFixed(1);
    return `color-mix(in srgb, var(--color-surface-standard-base) ${coverage}%, transparent) ${(x * 100).toFixed(1)}%`;
  }).join(", ");

  const geometry = $derived(SHAPES[shape]);
  const height = $derived(control > 0 ? control + geometry.fadeReach : geometry.fadeReach);

  /* The blur is full from the screen edge part way down the control, then
     eases out with flat ends (smoothstep), so it leaves no edge. Without a
     control it eases over the whole soft edge. */
  const blurMask = $derived.by(() => {
    const full =
      control > 0 ? `(${inset} + (${control}px - ${inset}) * ${geometry.fullDepth})` : "0px";
    const end = control > 0 ? `${control + geometry.overhang}px` : `${height}px`;
    const ease = Array.from({ length: STEPS + 1 }, (_, i) => {
      const t = i / STEPS;
      const coverage = (1 - t * t * (3 - 2 * t)).toFixed(3);
      return `rgba(0, 0, 0, ${coverage}) calc(var(--overscan) + ${full} + (${end} - ${full}) * ${t.toFixed(4)})`;
    });
    return `linear-gradient(var(--toward-content), black 0, ${ease.join(", ")})`;
  });
</script>

<!--
  A soft edge over content scrolling toward a screen edge: a backdrop blur,
  washed with the surface colour, under a light fade of it. Both show only while content is
  scrolled past the edge.
-->
<div
  class="soft-edge {edge}"
  class:active
  style:height="{height}px"
  style:--fade-stops={fadeStops}
  style:right="{gutter}px"
  aria-hidden="true"
>
  <div class="blur" style:mask-image={blurMask}></div>
  <div class="fade"></div>
</div>

<style>
  .soft-edge {
    position: absolute;
    left: 0;
    pointer-events: none;
    --toward-content: to bottom;
  }

  .top {
    top: 0;
  }

  .bottom {
    bottom: 0;
    --toward-content: to top;
  }

  .blur,
  .fade {
    position: absolute;
    inset: 0;
    opacity: 0;
    /* Matches iOS Animations.smooth, not --motion-fast: the activation fade
       is a slower, eased cross-fade than the fast interaction tier. */
    transition: opacity 250ms ease-in-out;
  }

  @media (prefers-reduced-motion: reduce) {
    .blur,
    .fade {
      transition: none;
    }
  }

  /* Opacity sits on the parts, not the soft edge: a faded parent would cut
     the backdrop filter off from the content behind. */
  .soft-edge.active .blur,
  .soft-edge.active .fade {
    opacity: 1;
  }

  /* A material, like the iOS system blur: a strong blur with a wash of the
     surface over it, which flattens the blurred content's contrast. */
  /* Runs past the screen edge, so the edge sits inside the blur: at its own
     boundary a blur has less to average and text there stays readable. The
     mask starts the same distance out. */
  .blur {
    --overscan: calc(2 * var(--soft-edge-blur, 20px));
    background: color-mix(
      in srgb,
      var(--color-surface-standard-base) var(--soft-edge-wash, 35%),
      transparent
    );
    backdrop-filter: blur(var(--soft-edge-blur, 20px));
  }

  .top .blur {
    top: calc(-1 * var(--overscan));
  }

  .bottom .blur {
    bottom: calc(-1 * var(--overscan));
  }

  .fade {
    background: linear-gradient(var(--toward-content), var(--fade-stops));
  }
</style>
