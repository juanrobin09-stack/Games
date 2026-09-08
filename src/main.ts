import '@/style.css';
import { Game } from '@/core/Game';
import { preloadStoneAsset } from '@/rendering/StoneAsset';

preloadStoneAsset();

function boot(): void {
  const canvas = document.getElementById('game-canvas');
  const uiRoot = document.getElementById('ui-root');
  if (!(canvas instanceof HTMLCanvasElement) || !(uiRoot instanceof HTMLElement)) {
    throw new Error('EMBERFALL: required root elements are missing from index.html');
  }
  new Game(canvas, uiRoot);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
