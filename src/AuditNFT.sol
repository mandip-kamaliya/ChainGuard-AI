// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AuditNFT
/// @notice ERC721 contract that mints audit certificates for vulnerability reports
/// @dev Each NFT represents a completed security audit with metadata stored on IPFS
/// @author ChainGuard AI Team
contract AuditNFT is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 private _tokenIdCounter;
    
    /// @dev Struct to store audit certificate metadata
    struct AuditCertificate {
        uint256 reportId;          // Associated vulnerability report ID
        address contractAddress;   // Address of the audited contract
        uint8 maxSeverity;         // Maximum severity level found
        uint256 auditTimestamp;    // When the audit was completed
        string auditor;            // Auditor identifier
        bool isValid;              // Certificate validity status
    }
    
    // Events
    /// @notice Emitted when an audit certificate NFT is minted
    /// @param tokenId ID of the minted NFT
    /// @param to Address that received the NFT
    /// @param contractAddress Address of the audited contract
    /// @param reportId Associated vulnerability report ID
    event CertificateMinted(
        uint256 indexed tokenId,
        address indexed to,
        address indexed contractAddress,
        uint256 reportId
    );
    
    /// @notice Emitted when a certificate is revoked
    /// @param tokenId ID of the revoked certificate
    /// @param reason Reason for revocation
    event CertificateRevoked(uint256 indexed tokenId, string reason);
    
    /// @notice Emitted when certificate metadata is updated
    /// @param tokenId ID of the updated certificate
    /// @param newTokenURI New IPFS metadata URI
    event MetadataUpdated(uint256 indexed tokenId, string newTokenURI);
    
    // State variables
    mapping(uint256 => AuditCertificate) public certificates;
    mapping(address => uint256[]) public contractCertificates;
    mapping(uint256 => bool) public validCertificates;
    
    address public securityRegistry; // Address of the SecurityRegistry contract
    address public chainGuardAddress; // Address of the ChainGuard contract
    string private _baseTokenURI;
    
    /// @dev Custom errors for gas efficiency
    error InvalidAddress();
    error NotAuthorized();
    error InvalidTokenId();
    error CertificateNotValid();
    error AlreadyRevoked();
    error InvalidRegistry();
    
    /// @notice Initializes the contract
    /// @param initialOwner Address that will own the contract
    /// @param _securityRegistry Address of the SecurityRegistry contract
    /// @param baseURI Base URI for token metadata
    constructor(
        address initialOwner,
        address _securityRegistry,
        string memory baseURI
    ) ERC721("ChainGuard Audit Certificate", "AUDIT") Ownable(initialOwner) {
        if (_securityRegistry == address(0)) revert InvalidAddress();
        securityRegistry = _securityRegistry;
        chainGuardAddress = msg.sender; // ChainGuard deploys this contract
        _baseTokenURI = baseURI;
    }
    
    /// @notice Mint an audit certificate NFT (only callable by SecurityRegistry)
    /// @param to Address that will receive the NFT
    /// @param contractAddress Address of the audited contract
    /// @param reportId Associated vulnerability report ID
    /// @param maxSeverity Maximum severity level found
    /// @param auditor Auditor identifier
    /// @param ipfsHash IPFS hash containing detailed audit metadata
    /// @return tokenId ID of the minted NFT
    function mintCertificate(
        address to,
        address contractAddress,
        uint256 reportId,
        uint8 maxSeverity,
        string memory auditor,
        string memory ipfsHash
    ) external nonReentrant returns (uint256) {
        if (msg.sender != securityRegistry && msg.sender != chainGuardAddress) revert NotAuthorized();
        if (to == address(0)) revert InvalidAddress();
        
        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;
        
        // Mint the NFT
        _safeMint(to, tokenId);
        
        // Store certificate metadata
        certificates[tokenId] = AuditCertificate({
            reportId: reportId,
            contractAddress: contractAddress,
            maxSeverity: maxSeverity,
            auditTimestamp: block.timestamp,
            auditor: auditor,
            isValid: true
        });
        
        validCertificates[tokenId] = true;
        
        // Set token URI to IPFS metadata
        string memory uri = string(abi.encodePacked(_baseTokenURI, ipfsHash));
        _setTokenURI(tokenId, uri);
        
        emit CertificateMinted(tokenId, to, contractAddress, reportId);
        
        return tokenId;
    }
    
    /// @notice Revoke an audit certificate
    /// @param tokenId ID of the certificate to revoke
    /// @param reason Reason for revocation
    /// @dev Only callable by contract owner or security registry
    function revokeCertificate(uint256 tokenId, string memory reason) external {
        if (!_isAuthorized(msg.sender, tokenId)) revert NotAuthorized();
        if (!validCertificates[tokenId]) revert CertificateNotValid();
        
        validCertificates[tokenId] = false;
        certificates[tokenId].isValid = false;
        
        emit CertificateRevoked(tokenId, reason);
    }
    
    /// @notice Update certificate metadata URI
    /// @param tokenId ID of the certificate
    /// @param ipfsHash New IPFS hash for metadata
    /// @dev Only callable by certificate owner
    function updateMetadata(uint256 tokenId, string memory ipfsHash) external {
        if (!_isAuthorized(msg.sender, tokenId)) revert NotAuthorized();
        if (!validCertificates[tokenId]) revert CertificateNotValid();
        
        string memory uri = string(abi.encodePacked(_baseTokenURI, ipfsHash));
        _setTokenURI(tokenId, uri);
        
        emit MetadataUpdated(tokenId, uri);
    }
    
    /// @notice Get certificate details
    /// @param tokenId ID of the certificate
    /// @return reportId Associated vulnerability report ID
    /// @return contractAddress Address of the audited contract
    /// @return maxSeverity Maximum severity level found
    /// @return auditTimestamp When the audit was completed
    /// @return auditor Auditor identifier
    /// @return isValid Certificate validity status
    function getCertificate(uint256 tokenId) external view returns (
        uint256 reportId,
        address contractAddress,
        uint8 maxSeverity,
        uint256 auditTimestamp,
        string memory auditor,
        bool isValid
    ) {
        AuditCertificate memory cert = certificates[tokenId];
        return (
            cert.reportId,
            cert.contractAddress,
            cert.maxSeverity,
            cert.auditTimestamp,
            cert.auditor,
            cert.isValid
        );
    }
    
    /// @notice Get all certificates for a contract
    /// @param contractAddress Address of the contract
    /// @return tokenIds Array of certificate token IDs for the contract
    function getContractCertificates(address contractAddress) external view returns (uint256[] memory) {
        uint256 totalSupply = _tokenIdCounter;
        uint256 count = 0;
        
        // First pass: count certificates for this contract
        for (uint256 i = 1; i <= totalSupply; i++) {
            if (certificates[i].contractAddress == contractAddress) {
                count++;
            }
        }
        
        // Second pass: collect token IDs
        uint256[] memory tokenIds = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= totalSupply; i++) {
            if (certificates[i].contractAddress == contractAddress) {
                tokenIds[index] = i;
                index++;
            }
        }
        
        return tokenIds;
    }
    
    /// @notice Get total number of valid certificates
    /// @return count Number of valid certificates
    function getValidCertificatesCount() external view returns (uint256 count) {
        uint256 totalSupply = _tokenIdCounter;
        
        for (uint256 i = 1; i <= totalSupply; i++) {
            if (validCertificates[i]) {
                count++;
            }
        }
    }
    
    /// @notice Set base token URI
    /// @param baseURI New base URI for token metadata
    /// @dev Only callable by contract owner
    function setBaseTokenURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }
    
    /// @notice Set security registry address
    /// @param _securityRegistry New security registry address
    /// @dev Only callable by contract owner
    function setSecurityRegistry(address _securityRegistry) external onlyOwner {
        if (_securityRegistry == address(0)) revert InvalidAddress();
        securityRegistry = _securityRegistry;
    }
    
    /// @notice Update the ChainGuard contract address
    /// @param _chainGuard New ChainGuard address
    /// @dev Only callable by contract owner
    function setChainGuardAddress(address _chainGuard) external onlyOwner {
        if (_chainGuard == address(0)) revert InvalidAddress();
        chainGuardAddress = _chainGuard;
    }
    
    /// @notice Get severity color for UI display
    /// @param severity Severity level (1=Low, 4=Critical)
    /// @return color Hex color code for the severity
    function getSeverityColor(uint8 severity) external pure returns (string memory) {
        if (severity == 4) return "#DC2626"; // Critical - Red
        if (severity == 3) return "#F97316"; // High - Orange
        if (severity == 2) return "#EAB308"; // Medium - Yellow
        return "#22C55E"; // Low - Green
    }
    
    /// @notice Get severity label
    /// @param severity Severity level (1=Low, 4=Critical)
    /// @return label Human-readable severity label
    function getSeverityLabel(uint8 severity) external pure returns (string memory) {
        if (severity == 4) return "CRITICAL";
        if (severity == 3) return "HIGH";
        if (severity == 2) return "MEDIUM";
        return "LOW";
    }
    
    // Override required functions
    /// @dev Returns the URI for the token metadata
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    /// @dev Checks if the given address is authorized to manage the token
    function _isAuthorized(address address_, uint256 tokenId) internal view returns (bool) {
        return (ownerOf(tokenId) == address_ || 
                getApproved(tokenId) == address_ || 
                isApprovedForAll(ownerOf(tokenId), address_) ||
                address_ == owner() ||
                address_ == securityRegistry);
    }
    
    /// @dev Override supportsInterface to include ERC721URIStorage
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
