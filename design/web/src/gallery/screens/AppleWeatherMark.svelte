<script lang="ts">
  import blackMark from "../../../../assets/icons/service/apple-weather-black.png";
  import whiteMark from "../../../../assets/icons/service/apple-weather-white.png";
</script>

<span class="weather-mark">
  <img class="light-mark" src={blackMark} alt="Apple Weather" width="99" height="18" />
  <img class="dark-mark" src={whiteMark} alt="Apple Weather" width="99" height="18" />
</span>

<style>
  .weather-mark {
    display: inline-flex;
    flex: none;
  }
  img {
    object-fit: contain;
  }
  .dark-mark {
    display: none;
  }
  :global([data-color-scheme="dark"]) .light-mark {
    display: none;
  }
  :global([data-color-scheme="dark"]) .dark-mark {
    display: block;
  }
</style>
