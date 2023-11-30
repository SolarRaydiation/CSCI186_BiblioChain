// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

contract BiblioChain {
    address public administrator; // the owner of the contract
    uint private nextBookID = 1;
    uint public fineAmount = 50000 wei; // 50,000 Wei fine for late book return
    uint public leaseDuration = 2 weeks; // Two weeks lease duration

    constructor() {
        administrator = msg.sender;
    }

    // Bibliochain is user-centered
    // Three categories of users: administator, librarian, and the user
    // 1) Administrators can enroll and unenroll librarians & users. They can also add, modify,
    // and remove books
    // 2) Librarians have the same permissions as the above, except for enrolling and unerolling
    // librarians
    // 3) Users can borrow books, return them, and renew the borrowing period. They will pay 
    // a pentaly if they have exceeded their borrowing period and have not returned their book

    struct Book {
        string bookName;
        string bookAuthor;
        string genre;
        string description;
        bool isBorrowed;
        bool doesExist;
    }

    struct User {
        bool isEnrolled;
        bool hasBorrowedBook;
        bool hasHoldOrder;
        uint borrowedBookID;
        uint dateBorrowed;
        uint dateDue;
        uint penaltyAmount; // Penalty amount for the user
    }

    mapping(address => User) public users;
    mapping(uint => Book) public books;
    mapping(address => bool) public isEnrolledAsLibrarian;

    // Array to hold user addresses
    address[] private userAddresses;

    /* ===================================
     * MODIFIERS
     =================================== */

    modifier isSuperUser() {
        require(msg.sender == administrator, "Request rejected. You are not the administrator.");
        _;
    }

    modifier isLibrarian() {
        require(isEnrolledAsLibrarian[msg.sender] == true, "Request rejected. You are not the librarian.");
        _;
    }

    modifier isSuperUserOrLibrarian() {
        require(
            msg.sender == administrator || isEnrolledAsLibrarian[msg.sender] == true,
            "Request rejected. You are not the administrator or librarian."
        );
        _;
    }

    modifier isUserEnrolled(address _address) {
        require(users[_address].isEnrolled == true, "Request rejected. The user is not enrolled.");
        _;
    }

    modifier doesBookExist(uint _bookID) {
        require(books[_bookID].doesExist == true, "Request rejected. The book does not exist.");
        _;
    }

    modifier isBookBorrowed(uint _bookID) {
        require(books[_bookID].isBorrowed == true, "Request rejected. The book is not borrowed by any user.");
        _;
    }

    modifier hasNoPenalty(address _userAddress) {
        require(users[_userAddress].penaltyAmount == 0, "Request rejected. User has an existing penalty.");
        _;
    }

    /* ===================================
     * FUNCTIONS AVAILABLE ONLY TO ADMINISTRATOR
     =================================== */

    function enrollLibrarian(address _address) external isSuperUser() {
        require(users[_address].isEnrolled == false, "Enrolled users can't become librarians.");
        require(administrator != _address, "Administrator need not apply to be librarian or user.");
        isEnrolledAsLibrarian[_address] = true;
    }

    function unenrollLibrarian(address _address) external isSuperUser() {
        isEnrolledAsLibrarian[_address] = false;
    }

    /* ===================================
     * FUNCTIONS AVAILABLE TO BOTH ADMINISTRATOR AND LIBRARIAN
     =================================== */

    // FOR (UN)ENROLLING USERS
    function enrollUser(address _userAddress) external isSuperUserOrLibrarian() {
        require(isEnrolledAsLibrarian[_userAddress] == false, "Requested rejected. Librarians cannot become users.");
        require(administrator != _userAddress, "Administrator need not apply to be librarian or user.");
        users[_userAddress].isEnrolled = true;
        userAddresses.push(_userAddress); // Add the user address to the array
    }

    function unenrollUser(address _userAddress) external isSuperUserOrLibrarian() isUserEnrolled(_userAddress) {
        require(users[_userAddress].hasBorrowedBook == false, "Request rejected. User has borrowed a book");
        require(users[_userAddress].hasHoldOrder == false, "Request rejected. User has a pending hold order.");

        // If the user has a penalty, we deduct it before unenrolling the user
        if (users[_userAddress].penaltyAmount > 0) {
            deductPenalty(_userAddress);
        }

        users[_userAddress].isEnrolled = false;

        // Remove the user address from the array
        for (uint i = 0; i < userAddresses.length; i++) {
            if (userAddresses[i] == _userAddress) {
                // Swap with the last element and pop
                userAddresses[i] = userAddresses[userAddresses.length - 1];
                userAddresses.pop();
                break;
            }
        }
    }

    // FOR MANAGING BOOK INVENTORY
    function incrementBookNumber() private {
        nextBookID += 1;
    }

    function addBook(
        string memory _bookName,
        string memory _bookAuthor,
        string memory _genre,
        string memory _description
    ) external isSuperUserOrLibrarian() {
        books[nextBookID].doesExist = true;
        books[nextBookID].bookName = _bookName;
        books[nextBookID].bookAuthor = _bookAuthor;
        books[nextBookID].genre = _genre;
        books[nextBookID].description = _description;
        incrementBookNumber();
    }

    function removeBook(uint _bookID) external isSuperUserOrLibrarian() doesBookExist(_bookID) {
        require(!books[_bookID].isBorrowed, "Request rejected. Book is currently borrowed.");
        books[_bookID].doesExist = false;
        books[_bookID].bookName = "";
        books[_bookID].bookAuthor = "";
        books[_bookID].genre = "";
        books[_bookID].description = "";
    }

    function modifyBookName(uint _bookID, string memory _bookName) external isSuperUserOrLibrarian() doesBookExist(_bookID) {
        require(books[_bookID].isBorrowed == false, "Request rejected. Books cannot be modified when borrowed by a user.");
        books[_bookID].bookName = _bookName;
    }

    function modifyBookAuthor(uint _bookID, string memory _bookAuthor) external isSuperUserOrLibrarian() doesBookExist(_bookID) {
        require(books[_bookID].isBorrowed == false, "Request rejected. Books cannot be modified when borrowed by a user.");
        books[_bookID].bookAuthor = _bookAuthor;
    }

    function modifyDescription(uint _bookID, string memory _description) external isSuperUserOrLibrarian() doesBookExist(_bookID) {
        require(books[_bookID].isBorrowed == false, "Request rejected. Books cannot be modified when borrowed by a user.");
        books[_bookID].description = _description;
    }

    function modifyGenre(uint _bookID, string memory _genre) external isSuperUserOrLibrarian() doesBookExist(_bookID) {
        require(books[_bookID].isBorrowed == false, "Request rejected. Books cannot be modified when borrowed by a user.");
        books[_bookID].genre = _genre;
    }

    // FUNCTION TO CHARGE PENALTY FOR LATE BOOK RETURN
    function chargePenalty(address _userAddress) private {
        //require(users[_userAddress].hasBorrowedBook, "Request rejected. User has not borrowed any book.");
        uint currentDate = block.timestamp;
        //require(currentDate > users[_userAddress].dateDue, "Request rejected. Book is not overdue yet.");
        uint overdueDays = (currentDate - users[_userAddress].dateDue) / 1 days;
        uint penaltyAmount = fineAmount * overdueDays;

        // Deduct penalty amount from user's balance or take other appropriate action
        // For simplicity, we'll store the penalty amount in the user's struct
        users[_userAddress].penaltyAmount += penaltyAmount;

        // Emit an event with penalty details
        emit PenaltyCharged(_userAddress, users[_userAddress].borrowedBookID, penaltyAmount);
    }

    function deductPenalty(address _userAddress) private {
        // Implement the logic to deduct the penalty amount from the user's balance
        // In a real-world scenario, you would need to implement a payment system or use a token transfer function.
        // For simplicity, we'll set the penalty amount to 0 in the user's struct.
        users[_userAddress].penaltyAmount = 0;
        users[_userAddress].hasHoldOrder = false;
    }

    event PenaltyCharged(address indexed userAddress, uint indexed borrowedBookID, uint penaltyAmount);

    // FUNCTION TO ITERATE OVER USER ADDRESSES
    function getAllUserAddresses() external view returns (address[] memory) {
        return userAddresses;
    }

    /* ===================================
     * FUNCTIONS AVAILABLE TO THE USER
     =================================== */

    // FUNCTION FOR USER TO PAY PENALTY AND LIFT THE PENALTY
    function payPenalty() external isUserEnrolled(msg.sender) {
        require(users[msg.sender].penaltyAmount > 0, "Request rejected. User does not have any pending penalty.");

        // Implement the logic for the user to pay the penalty amount
        // For simplicity, we'll call the deductPenalty function to set the penalty amount to 0.
        deductPenalty(msg.sender);
    }

    // FUNCTION FOR USER TO BORROW A BOOK
    function borrowBook(uint _bookID) external isUserEnrolled(msg.sender) doesBookExist(_bookID) hasNoPenalty(msg.sender) {
        require(!books[_bookID].isBorrowed, "Request rejected. The book is already borrowed.");
        require(!users[msg.sender].hasHoldOrder, "Request rejected. You cannot borrow books if you have a hold order.");

        // Implement the logic for the user to borrow a book
        // For simplicity, we'll set the book status to borrowed and update user's information.
        books[_bookID].isBorrowed = true;
        users[msg.sender].hasBorrowedBook = true;
        users[msg.sender].borrowedBookID = _bookID;
        users[msg.sender].dateBorrowed = block.timestamp;
        users[msg.sender].dateDue = block.timestamp + leaseDuration;
    }

    // if the user has borrowed a book and is not late/overdue for returning it,
    // they can renew it again for another two weeks
    function renewLease() external isUserEnrolled(msg.sender) {
        require(users[msg.sender].hasBorrowedBook, "Request rejected. User has not borrowed any book.");
        require(!isBookOverdue(msg.sender), "Request rejected. Book is overdue.");

        // Extend the lease for another two weeks
        users[msg.sender].dateDue += leaseDuration;
    }

    // Function to check if the borrowed book is overdue
    function isBookOverdue(address _userAddress) private view returns (bool) {
        require(users[_userAddress].hasBorrowedBook, "User has not borrowed any book.");

        uint currentDate = block.timestamp;

        return currentDate > users[_userAddress].dateDue;
    }

    // return book
    function returnBook() external isUserEnrolled(msg.sender) {
        require(users[msg.sender].hasBorrowedBook, "User has not borrowed any book.");
        if (block.timestamp > users[msg.sender].dateDue) {
            users[msg.sender].hasHoldOrder = true;
            chargePenalty(msg.sender);
        }

        users[msg.sender].hasBorrowedBook = false;
        books[users[msg.sender].borrowedBookID].isBorrowed = false;
        users[msg.sender].borrowedBookID = 0;

        // no need to change dateBorrowed and dateDue
        // they are no longer used anyways
    }

    // this is a tester function meant to simulate a situation
    // where the user is late in returning their book on time
    /* function setBookAsLate() external isUserEnrolled(msg.sender) {
        users[msg.sender].dateDue = 0;
    } */
}
