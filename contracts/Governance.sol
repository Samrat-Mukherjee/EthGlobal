// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Governance {
    enum ProposalState {
        Unassigned, // 0 Default on-chain state
        Pending, // 1 Returned by state() after submission but before voting begins
        Active, // 2 Returned by state() after voting begins but before voting ends
        Queued, // 3 Returned by state() after voting ends but before execution
        Defeated, // 4 Stored on-chain by execute() if proposal was defeated
        Succeeded, // 5 Stored on-chain by execute() if proposal succeeded
        Expired // 6 Stored on-chain by execute() if proposal didn't reach quorum
    }

    enum ProposalType {
        IssueGrant,
        ModifyGrantSize
    }

    struct ProposalData {
        uint256 voteBegins;
        uint256 voteEnds;
        uint256 votesFor;
        uint256 votesAgainst;
        ProposalState propState;
        ProposalType propType;
        address recipient;
        uint256 ethGrant;
        uint256 newETHGrant;
    }

    ProposalData[] private proposals;
    uint256 private quorum = 3;
    // Member Address => Proposal ID => True if member has voted
    mapping(address => mapping(uint256 => bool)) public memberHasVoted;

    uint256 public reviewPeriod = 30 seconds;
    uint256 public votingPeriod = 1 minutes;

    uint256 public grantAmount = 1 ether;
    uint256 public availableETH;

    constructor() payable {
        availableETH = msg.value;
    }

    /// @notice Returns the current state of a Proposal
    function state(uint256 propID) public view returns (ProposalState) {
        ProposalData storage proposal = proposals[propID];
        ProposalState propState = proposal.propState;

        // Unassigned are any Proposals that have not been executed yet
        if (propState != ProposalState.Unassigned) return propState;

        uint256 voteBegins = proposal.voteBegins;

        // Proposals that don't exist will have a 0 voting begin date
        if (voteBegins == 0) revert("Invalid ID");
        // If the voting begin date is in the future, then voting has not begun yet
        if (voteBegins >= block.timestamp) return ProposalState.Pending;

        uint256 voteEnds = proposal.voteEnds;

        // If the voting end date is in the future, then voting is still active
        if (voteEnds >= block.timestamp) return ProposalState.Active;

        // If none of the above is true, then voting is over and this Proposal is queued for execution
        return ProposalState.Queued;
    }

    /// @dev Determines if number of votes submitted were sufficient to achieve quorum
    function _quorumReached(uint256 votesFor, uint256 votesAgainst)
        private
        view
        returns (bool quorumReached)
    {
        quorumReached = (votesFor + votesAgainst >= quorum);
        //********************************************************
    }

    /// @dev Applies vote success formula to determine if voting ratio led to successful outcome
    function _voteSucceeded(uint256 votesFor, uint256 votesAgainst)
        private
        pure
        returns (bool voteSucceeded)
    {
        voteSucceeded = votesFor > votesAgainst; // 50% + 1 majority
        /**
         ALTERNATIVE SYSTEMS:
            2/3 Supermajority:
            voteSucceeded = votesFor >= votesAgainst * 2;

            3/5 Majority
            voteSucceeded = votesFor * 2 >= votesAgainst * 3

            X/Y Majority, 
            voteSucceeded = votesFor * (Y - X) >= votesAgainst * X
         */
    }

    /// @dev Tallies up all votes to determine if Proposal is Succeeded, Defeated, or Expired
    function _tallyVotes(uint256 propID) private view returns (ProposalState) {
        ProposalData storage proposal = proposals[propID];

        uint256 votesFor = proposal.votesFor;
        uint256 votesAgainst = proposal.votesAgainst;
        bool quorumReached = _quorumReached(votesFor, votesAgainst);

        if (quorumReached == false) return ProposalState.Expired;
        else if (_voteSucceeded(votesFor, votesAgainst))
            return ProposalState.Succeeded;
        else return ProposalState.Defeated;
    }

    // //*** PROPOSE ***\\

    /// @dev Submits a Proposal to the proposals array
    function _submitProposal(
        ProposalType propType,
        address recipient,
        uint256 amount,
        uint256 newGrantAmount
    ) private {
        uint256 votingBeginDate = block.timestamp + reviewPeriod;
        ProposalData memory newProposal = ProposalData({
            voteBegins: votingBeginDate,
            voteEnds: votingBeginDate + votingPeriod,
            votesFor: 0,
            votesAgainst: 0,
            propState: ProposalState.Unassigned,
            propType: propType,
            recipient: recipient,
            ethGrant: amount,
            newETHGrant: newGrantAmount
        });
        proposals.push(newProposal);
    }

    /// @notice Submits a new grant request
    function submitNewGrant(address recipient) public {
        uint256 grantAmount_ = grantAmount;
        require(availableETH >= grantAmount_, "Insufficient ETH");

        availableETH -= grantAmount_;

        _submitProposal(ProposalType.IssueGrant, recipient, grantAmount_, 0);
    }

    /// @notice Submits a new grant amount change request
    function submitNewAmountChange(uint256 newGrantAmount) public {
        require(newGrantAmount > 0, "Invalid amount");

        _submitProposal(
            ProposalType.ModifyGrantSize,
            address(0),
            0,
            newGrantAmount
        );
    }

    //*** VOTE ***\\
    /// @dev Performs all checks required for caller to vote
    modifier voteChecks(uint256 propID) {
        require(state(propID) == ProposalState.Active, "Proposal inactive");
        require(
            memberHasVoted[msg.sender][propID] == false,
            "Member already voted"
        );
        _;
    }

    /// @dev Submits a vote for or against to Proposal propID
    function _submitVote(uint256 propID, bool votedFor) private {
        ProposalData storage proposal = proposals[propID];

        if (votedFor) proposal.votesFor++;
        else proposal.votesAgainst++;

        memberHasVoted[msg.sender][propID] = true;
    }

    // TO DISCUSS: How to implement burn voting by adding a second input to each vote function
    function voteFor(uint256 propID) public voteChecks(propID) {
        _submitVote(propID, true);
    }

    function voteAgainst(uint256 propID) public voteChecks(propID) {
        _submitVote(propID, false);
    }

    //*** EXECUTE ***\\
    /// @notice Executes a Proposal when it is in the Queued state
    // NOTE: This function is vulnerable to reentrancy -- move _setState(propID) to line 188
    function execute(uint256 propID) public {
        ProposalData storage proposal = proposals[propID];
        ProposalState propState = state(propID);

        require(
            propState == ProposalState.Queued,
            "Proposal not queued for execution"
        );

        propState = _tallyVotes(propID);
        ProposalType propType = proposal.propType;

        if (propState == ProposalState.Succeeded) {
            if (propType == ProposalType.IssueGrant) {
                _issueGrant(propID);
            } else if (propType == ProposalType.ModifyGrantSize) {
                _modifyGrantSize(propID);
            }
        } else {
            if (propType == ProposalType.IssueGrant) {
                availableETH += proposal.ethGrant;
            }
        }

        _setState(propID);
    }

    /// @dev Called by execute() when ProposalType is IssueGrant
    function _issueGrant(uint256 propID) private {
        ProposalData storage proposal = proposals[propID];

        (bool success, ) = proposal.recipient.call{value: proposal.ethGrant}(
            ""
        );

        if (!success) {
            availableETH += proposal.ethGrant;
        }
    }

    /// @dev Called by execute() when ProposalType is ModifyGrantSize
    function _modifyGrantSize(uint256 propID) private {
        ProposalData storage proposal = proposals[propID];

        grantAmount = proposal.newETHGrant;
    }

    /// @dev Called by execute() to update the on-chain state of a Proposal
    function _setState(uint256 propID) private {
        ProposalData storage proposal = proposals[propID];
        uint256 votesFor = proposal.votesFor;
        uint256 votesAgainst = proposal.votesAgainst;
        bool quorumReached = _quorumReached(votesFor, votesAgainst);

        if (quorumReached == false) proposal.propState = ProposalState.Expired;
        else if (_voteSucceeded(votesFor, votesAgainst))
            proposal.propState = ProposalState.Succeeded;
        else proposal.propState = ProposalState.Defeated;
    }

    // //*** GETTER FUNCTIONS ***\\
    function getTotalProposals() public view returns (uint256 totalProposals) {
        totalProposals = proposals.length;
    }

    function getProposal(uint256 propID)
        public
        view
        returns (ProposalData memory proposal)
    {
        proposal = proposals[propID];
        proposal.propState = state(propID);

        return proposal;
    }

    function getTimestamp() public view returns (uint256 timestamp) {
        return block.timestamp;
    }

    function getReviewTimeRemaining(uint256 propID)
        public
        view
        returns (uint256 timeRemaining)
    {
        ProposalData storage proposal = proposals[propID];

        if (state(propID) == ProposalState.Pending)
            return proposal.voteBegins - getTimestamp();
        else return 0;
    }

    function getVoteTimeRemaining(uint256 propID)
        public
        view
        returns (uint256 timeRemaining)
    {
        ProposalData storage proposal = proposals[propID];

        if (state(propID) == ProposalState.Active)
            return proposal.voteEnds - getTimestamp();
        else return 0;
    }

    function getQuorum() public view returns (uint256) {
        return quorum;
    }
}
