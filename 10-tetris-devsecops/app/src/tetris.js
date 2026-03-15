const canvas = document.getElementById('board');
const ctx = canvas.getContext('2d');
const nextCanvas = document.getElementById('next');
const nextCtx = nextCanvas.getContext('2d');

const COLS = 10;
const ROWS = 20;
const BLOCK = 30;
const NEXT_BLOCK = 20;

const COLORS = [
    null,
    '#00f5ff',  // I - cyan
    '#0000ff',  // J - blue
    '#ff8c00',  // L - orange
    '#ffff00',  // O - yellow
    '#00ff00',  // S - green
    '#9b30ff',  // T - purple
    '#ff0000',  // Z - red
];

const SHAPES = [
    [],
    [[0,0,0,0],[1,1,1,1],[0,0,0,0],[0,0,0,0]], // I
    [[2,0,0],[2,2,2],[0,0,0]],                   // J
    [[0,0,3],[3,3,3],[0,0,0]],                   // L
    [[4,4],[4,4]],                                 // O
    [[0,5,5],[5,5,0],[0,0,0]],                   // S
    [[0,6,0],[6,6,6],[0,0,0]],                   // T
    [[7,7,0],[0,7,7],[0,0,0]],                   // Z
];

let board, piece, nextPiece, score, level, lines, gameOver, paused, dropInterval, lastDrop;

function createBoard() {
    return Array.from({ length: ROWS }, () => new Array(COLS).fill(0));
}

function randomPiece() {
    const id = Math.floor(Math.random() * 7) + 1;
    return {
        shape: SHAPES[id].map(row => [...row]),
        color: id,
        x: Math.floor(COLS / 2) - Math.ceil(SHAPES[id][0].length / 2),
        y: 0,
    };
}

function rotate(shape) {
    const N = shape.length;
    const rotated = shape.map((row, i) => row.map((_, j) => shape[N - 1 - j][i]));
    return rotated;
}

function valid(shape, px, py) {
    for (let y = 0; y < shape.length; y++) {
        for (let x = 0; x < shape[y].length; x++) {
            if (shape[y][x]) {
                const nx = px + x;
                const ny = py + y;
                if (nx < 0 || nx >= COLS || ny >= ROWS) return false;
                if (ny >= 0 && board[ny][nx]) return false;
            }
        }
    }
    return true;
}

function merge() {
    piece.shape.forEach((row, y) => {
        row.forEach((val, x) => {
            if (val && piece.y + y >= 0) {
                board[piece.y + y][piece.x + x] = val;
            }
        });
    });
}

function clearLines() {
    let cleared = 0;
    for (let y = ROWS - 1; y >= 0; y--) {
        if (board[y].every(cell => cell !== 0)) {
            board.splice(y, 1);
            board.unshift(new Array(COLS).fill(0));
            cleared++;
            y++;
        }
    }
    if (cleared > 0) {
        const points = [0, 100, 300, 500, 800];
        score += points[cleared] * level;
        lines += cleared;
        level = Math.floor(lines / 10) + 1;
        dropInterval = Math.max(100, 1000 - (level - 1) * 80);
        document.getElementById('score').textContent = score;
        document.getElementById('level').textContent = level;
        document.getElementById('lines').textContent = lines;
    }
}

function drawBlock(context, x, y, color, size) {
    context.fillStyle = COLORS[color];
    context.fillRect(x * size, y * size, size - 1, size - 1);
    context.fillStyle = 'rgba(255,255,255,0.15)';
    context.fillRect(x * size, y * size, size - 1, 3);
    context.fillRect(x * size, y * size, 3, size - 1);
}

function draw() {
    ctx.fillStyle = '#000011';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Draw grid lines
    ctx.strokeStyle = 'rgba(255,255,255,0.03)';
    for (let x = 0; x <= COLS; x++) {
        ctx.beginPath(); ctx.moveTo(x * BLOCK, 0); ctx.lineTo(x * BLOCK, ROWS * BLOCK); ctx.stroke();
    }
    for (let y = 0; y <= ROWS; y++) {
        ctx.beginPath(); ctx.moveTo(0, y * BLOCK); ctx.lineTo(COLS * BLOCK, y * BLOCK); ctx.stroke();
    }

    board.forEach((row, y) => {
        row.forEach((val, x) => {
            if (val) drawBlock(ctx, x, y, val, BLOCK);
        });
    });

    if (piece) {
        // Ghost piece
        let ghostY = piece.y;
        while (valid(piece.shape, piece.x, ghostY + 1)) ghostY++;
        if (ghostY !== piece.y) {
            piece.shape.forEach((row, y) => {
                row.forEach((val, x) => {
                    if (val) {
                        ctx.fillStyle = 'rgba(255,255,255,0.08)';
                        ctx.fillRect((piece.x + x) * BLOCK, (ghostY + y) * BLOCK, BLOCK - 1, BLOCK - 1);
                    }
                });
            });
        }

        piece.shape.forEach((row, y) => {
            row.forEach((val, x) => {
                if (val && piece.y + y >= 0) drawBlock(ctx, piece.x + x, piece.y + y, val, BLOCK);
            });
        });
    }

    if (gameOver) {
        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#ff0000';
        ctx.font = 'bold 30px Courier New';
        ctx.textAlign = 'center';
        ctx.fillText('GAME OVER', canvas.width / 2, canvas.height / 2 - 15);
        ctx.fillStyle = '#ffffff';
        ctx.font = '16px Courier New';
        ctx.fillText('Score: ' + score, canvas.width / 2, canvas.height / 2 + 20);
    }

    if (paused && !gameOver) {
        ctx.fillStyle = 'rgba(0,0,0,0.5)';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#00f5ff';
        ctx.font = 'bold 24px Courier New';
        ctx.textAlign = 'center';
        ctx.fillText('PAUSED', canvas.width / 2, canvas.height / 2);
    }
}

function drawNext() {
    nextCtx.fillStyle = 'rgba(0,0,0,0.3)';
    nextCtx.fillRect(0, 0, nextCanvas.width, nextCanvas.height);
    if (!nextPiece) return;
    const offsetX = (nextCanvas.width / NEXT_BLOCK - nextPiece.shape[0].length) / 2;
    const offsetY = (nextCanvas.height / NEXT_BLOCK - nextPiece.shape.length) / 2;
    nextPiece.shape.forEach((row, y) => {
        row.forEach((val, x) => {
            if (val) drawBlock(nextCtx, x + offsetX, y + offsetY, val, NEXT_BLOCK);
        });
    });
}

function drop() {
    if (valid(piece.shape, piece.x, piece.y + 1)) {
        piece.y++;
    } else {
        merge();
        clearLines();
        piece = nextPiece;
        nextPiece = randomPiece();
        drawNext();
        if (!valid(piece.shape, piece.x, piece.y)) {
            gameOver = true;
            document.getElementById('start-btn').disabled = false;
            document.getElementById('pause-btn').disabled = true;
        }
    }
}

function hardDrop() {
    while (valid(piece.shape, piece.x, piece.y + 1)) {
        piece.y++;
        score += 2;
    }
    document.getElementById('score').textContent = score;
    drop();
}

function gameLoop(timestamp) {
    if (gameOver) { draw(); return; }
    if (!paused) {
        if (timestamp - lastDrop > dropInterval) {
            drop();
            lastDrop = timestamp;
        }
        draw();
    }
    requestAnimationFrame(gameLoop);
}

function startGame() {
    board = createBoard();
    score = 0; level = 1; lines = 0;
    gameOver = false; paused = false;
    dropInterval = 1000; lastDrop = 0;
    piece = randomPiece();
    nextPiece = randomPiece();
    document.getElementById('score').textContent = '0';
    document.getElementById('level').textContent = '1';
    document.getElementById('lines').textContent = '0';
    document.getElementById('start-btn').disabled = true;
    document.getElementById('pause-btn').disabled = false;
    drawNext();
    requestAnimationFrame(gameLoop);
}

function togglePause() {
    paused = !paused;
    document.getElementById('pause-btn').textContent = paused ? 'RESUME' : 'PAUSE';
    if (!paused) requestAnimationFrame(gameLoop);
    else draw();
}

document.addEventListener('keydown', (e) => {
    if (gameOver || !piece) return;
    if (e.key === 'p' || e.key === 'P') { togglePause(); return; }
    if (paused) return;

    switch (e.key) {
        case 'ArrowLeft':
            if (valid(piece.shape, piece.x - 1, piece.y)) piece.x--;
            break;
        case 'ArrowRight':
            if (valid(piece.shape, piece.x + 1, piece.y)) piece.x++;
            break;
        case 'ArrowDown':
            if (valid(piece.shape, piece.x, piece.y + 1)) { piece.y++; score += 1; }
            break;
        case 'ArrowUp':
            const rotated = rotate(piece.shape);
            if (valid(rotated, piece.x, piece.y)) piece.shape = rotated;
            break;
        case ' ':
            e.preventDefault();
            hardDrop();
            break;
    }
    document.getElementById('score').textContent = score;
    draw();
});

draw();
drawNext();
