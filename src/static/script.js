import Alpine from 'alpinejs';

function kanban() {
  return {
    boards: [],
    currentBoardId: 0,
    showCreateBoardForm: false,
    newBoard: {
      name: '',
      code: '',
      description: '',
    },
    cards: [],
    showCreateForm: false,
    selectedCard: null,
    isEditingCard: false,
    editCard: {
      id: '',
      title: '',
      description: '',
    },
    newCard: {
      column: 0,
      title: '',
      description: ''
    },
    // Drag and drop
    cardDraggedId: null,
    cardDragOverColumn: null,

    init() {
      this.loadBoards();
      this.loadCards();
    },

    get currentBoard() {
      return this.boards.find(b => b.id === this.currentBoardId);
    },

    cardsForColumn(columnId) {
      return this.cards.filter(card => card.column === columnId);
    },

    startEditingCard() {
      this.editCard.id = this.selectedCard.id;
      this.editCard.title = this.selectedCard.title;
      this.editCard.description = this.selectedCard.description;
      this.isEditingCard = true;
    },

    cancelEditCard() {
      this.editCard.id = "";
      this.editCard.title = "";
      this.editCard.description = "";
      this.isEditingCard = false;
    },

    formatTimestamp(ts) {
      return ts ? new Date(ts * 1000).toLocaleString() : "";
    },

    async loadBoards() {
      try {
        const response = await fetch('/api/boards');
        if (!response.ok) {
          console.error('Failed to load boards:', response.status);
        }
        this.boards = await response.json();
      } catch (error) {
        console.error('Error loading boards:', error);
      }
    },

    async createBoard() {
      await fetch('api/boards', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: this.newBoard.name,
          code: this.newBoard.code,
          description: this.newBoard.description
        })
      });

      this.newBoard = { name: '', code: '', description: '' };
      this.showCreateBoardForm = false;
      await this.loadBoards();
    },

    async loadCards() {
      try {
        const response = await fetch(`/api/boards/${this.currentBoardId}/cards`);
        if (!response.ok) {
          console.error('Failed to load cards:', response.status);
          return;
        }
        this.cards = await response.json();
      } catch (error) {
        console.error('Error loading cards:', error);
      }
    },

    async createCard() {
      await fetch('/api/cards', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          column: this.newCard.column,
          title: this.newCard.title,
          description: this.newCard.description,
          board_id: this.currentBoardId,
        })
      });

      // Reset form
      this.newCard.title = '';
      this.newCard.description = '';
      this.showCreateForm = false;

      // Refresh the entire list
      await this.loadCards();
    },

    async updateCard() {
      await fetch('/api/cards/' + this.editCard.id, {
        method: 'PATCH',
        headers: {
          'Content-type': 'application/json',
        },
        body: JSON.stringify({
          title: this.editCard.title,
          description: this.editCard.description
        })
      });

      const cardId = this.selectedCard.id;
      await this.loadCards();
      this.selectedCard = this.cards.find(c => c.id === cardId);
      this.cancelEditCard();
    },

    async moveCardToColumn(newColumn) {
      // Convert string to number (select returns strings)
      const columnNum = parseInt(newColumn, 10);
      console.log("COUCOU");

      // Don't do anything if it's the same column
      if (this.selectedCard.column === columnNum) return;

      const cardId = this.selectedCard.id;

      await fetch(`/api/cards/${cardId}/column`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ column: columnNum })
      });

      await this.loadCards();
      this.selectedCard = this.cards.find(c => c.id === cardId);
    },

    async moveCardToBoard(newBoardId) {
      const boardId = parseInt(newBoardId, 10);

      // Don't do anything if it's the same board
      if (this.selectedCard.board_id === boardId) return;

      const cardId = this.selectedCard.id;

      await fetch(`/api/cards/${cardId}/board`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ board_id: boardId })
      });

      // Reload cards and close modal since card moved to different board
      await this.loadCards();
      this.selectedCard = null;
    },

    onCardDragStart(cardId, event) {
      this.cardDraggedId = cardId;
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/html', event.target.innerHTML);
      event.target.style.opacity = 0.8;
    },

    onCardDragEnd(event) {
      event.target.style.opacity = 1;
      this.cardDraggedId = null;
      this.cardDragOverColumn = null;
    },

    onCardDragOver(event) {
      if (event.preventDefault) {
        event.preventDefault();
      }
      event.dataTransfer.dropEffet = 'move';
      return false;
    },

    onCardDragEnterColumn(columnNum, event) {
      event.preventDefault();
      this.cardDragOverColumn = columnNum;
    },

    onCardDragLeaveColumn() {
      if (!event.currentTarget.contains(event.relatedTarget)) {
        this.cardDragOverColumn = null;
      }
    },

    async onCardDropInColumn(columnNum, event) {
      if (event.stopPropagation) {
        event.stopPropagation();
      }

      const draggedCard = this.cards.find(c => c.id === this.cardDraggedId);

      if (draggedCard && draggedCard.column != columnNum) {
        await fetch(`/api/cards/${this.cardDraggedId}/column`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ column: columnNum })
        });

        await this.loadCards();
      }

      this.cardDragOverColumn = null;
      return false;
    }
  }
}

window.Alpine = Alpine;
window.kanban = kanban;

Alpine.start();
