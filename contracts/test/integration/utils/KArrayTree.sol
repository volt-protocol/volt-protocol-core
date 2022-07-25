pragma solidity =0.8.13;

library KArrayTree {
    struct Node {
        mapping(uint256 => Node) childMap;
        uint256[] childArray;
        bytes32 role;
    }

    /// @notice function that inserts a new node at the given node
    /// @param self the element to add another node to
    /// @param keyToAdd the key in the new element
    function insert(Node storage self, bytes32 keyToAdd)
        internal
        returns (bool, Node storage)
    {
        require(!exists(self, keyToAdd), "cannot insert duplicate");
        uint256 index = self.childArray.length; /// index of the new element

        self.childArray.push(index);
        Node storage newElem = self.childMap[index];
        newElem.role = keyToAdd;

        return (true, newElem);
    }

    /// @notice function that inserts a new node at the given node
    /// @param self the element to add another node to
    /// @param keyToFind the key at which to insert the new element
    /// @param keyToAdd the key in the new element
    function insert(
        Node storage self,
        bytes32 keyToFind,
        bytes32 keyToAdd
    ) internal returns (bool, Node storage) {
        require(!exists(self, keyToAdd), "cannot insert duplicate");
        (bool found, Node storage elem) = traverse(self, keyToFind);

        if (found) {
            uint256 index = elem.childArray.length;
            insert(elem, keyToAdd);
            return (true, elem.childMap[index]);
        }

        return (false, self);
    }

    /// @notice function that traverses the tree to find the key
    /// @param root pointer to the root node
    /// @param key the role being searched for within the tree
    /// @return true and pointer to first key found, return false and incorrect pointer if not
    function traverse(Node storage root, bytes32 key)
        internal
        returns (bool, Node storage)
    {
        if (root.role == key) {
            return (true, root);
        }

        uint256 len = root.childArray.length;
        for (uint256 i = 0; i < len; i++) {
            (bool valid, Node storage elem) = traverse(
                root.childMap[root.childArray[i]],
                key
            );
            if (valid) {
                return (true, elem);
            }
        }

        return (false, root);
    }

    /// @notice return number of all immediate children
    /// @param root the node to return length of all immediate children from
    function getCountImmediateChildren(Node storage root)
        internal
        returns (uint256)
    {
        return root.childArray.length;
    }

    /// @notice function to return the depth of the tree
    /// @param root the node to return the depth from
    /// @param currentDepth the current recorded tree depth
    /// @return the depth of the tree
    function treeDepth(Node storage root, uint256 currentDepth)
        internal
        returns (uint256)
    {
        uint256 len = root.childArray.length;

        if (len == 0) {
            return currentDepth;
        }

        uint256 maxDepth = currentDepth;

        for (uint256 i = 0; i < len; i++) {
            uint256 newDepth = treeDepth(
                root.childMap[root.childArray[i]],
                currentDepth + 1
            );
            if (newDepth > maxDepth) {
                maxDepth = newDepth;
            }
        }

        return maxDepth;
    }

    function getMaxDepth(Node storage root) internal returns (uint256) {
        return treeDepth(root, 1);
    }

    function exists(Node storage root, bytes32 key) internal returns (bool) {
        (bool found, ) = traverse(root, key);
    }

    /// @notice delete all child nodes recursively
    /// @param root pointer to the start of the tree where all beneath will be dropped
    function free(Node storage root) internal {
        uint256 len = root.childArray.length;
        if (len == 0) {
            return;
        }

        for (uint256 i = 0; i < len; i++) {
            free(root.childMap[root.childArray[i]]);
        }

        for (uint256 i = 0; i < len; i++) {
            delete root.childMap[root.childArray[i]];
            delete root.childArray[i];
        }
    }
}
