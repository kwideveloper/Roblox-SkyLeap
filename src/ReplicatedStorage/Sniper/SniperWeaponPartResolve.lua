-- Resolves weapon geometry when a Model/Folder shares the same name as the actual BasePart
-- (e.g. Sniper.Barrel (Model) > Barrel (MeshPart), Sniper.Muzzle (Model) > Muzzle (Part)).

local SniperWeaponPartResolve = {}

function SniperWeaponPartResolve.findFirstBasePartNamed(root: Instance?, partName: string): BasePart?
	if root == nil or partName == nil or partName == "" then
		return nil
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == partName and d:IsA("BasePart") then
			return d :: BasePart
		end
	end
	return nil
end

return SniperWeaponPartResolve
